//! A hook event as the island reads it (`HookEvent`,
//! `Sources/MorrowCore/Models.swift`): the fields the reducer routes on,
//! the tool's label and description, over the raw payload.

use std::sync::LazyLock;

use regex::Regex;
use serde_json::Value;

use super::json;
use crate::JsonObject;
use crate::intake::{SourceCatalog, normalized_supported_source};

/// `HookEvent`.
#[derive(Clone, Debug, PartialEq)]
pub struct HookEvent {
    pub event_name: String,
    /// The card it is filed under (`cardSessionId(forRawSessionId:in:)`).
    pub session_id: Option<String>,
    pub tool_name: Option<String>,
    pub tool_use_id: Option<String>,
    /// The subagent it comes from, when its source marks one by `agent_id`.
    pub agent_id: Option<String>,
    pub tool_input: Option<JsonObject>,
    /// The full payload.
    pub raw_json: JsonObject,
}

/// `ToolActivityCategory`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ToolActivityCategory {
    Reading,
    Searching,
    Editing,
    Shell,
    Browser,
    Mcp,
    Delegation,
    Question,
    Other,
}

impl HookEvent {
    /// `HookEvent(json:)`: `None` when the payload names no event. `sources`
    /// is what `normalizedSupportedSource` reads from `UserDefaults`.
    pub fn new(json: JsonObject, sources: &SourceCatalog) -> Option<Self> {
        let event_name = first_string(
            &json,
            &[
                "hook_event_name",
                "hookEventName",
                "event_name",
                "eventName",
            ],
        )?;
        let session_id = first_string(&json, &["session_id", "sessionId"])
            .map(|raw| card_session_id(&raw, &json));
        let tool_name = first_string(&json, &["tool_name", "toolName", "tool", "name"])
            .or_else(|| {
                first_string_nested(
                    &json,
                    &["tool", "payload", "data"],
                    &["name", "tool_name", "toolName"],
                )
            })
            .or_else(|| first_string_nested(&json, &["toolCall"], &["name"]));
        let tool_use_id = first_string(
            &json,
            &["tool_use_id", "toolUseId", "toolCallId", "_pi_tool_call_id"],
        )
        .or_else(|| {
            first_string_nested(
                &json,
                &["tool", "tool_use", "toolUse", "payload", "data"],
                &["id", "tool_use_id", "toolUseId"],
            )
        });
        let tool_input = first_object(
            &json,
            &[
                "tool_input",
                "toolInput",
                "input",
                "arguments",
                "args",
                "params",
            ],
        )
        .or_else(|| {
            ["tool", "payload", "data"].iter().find_map(|container| {
                first_object(
                    json::object(json.get(*container))?,
                    &[
                        "input",
                        "tool_input",
                        "toolInput",
                        "arguments",
                        "args",
                        "params",
                    ],
                )
            })
        })
        .or_else(|| first_object(json::object(json.get("toolCall"))?, &["args"]))
        .cloned();
        let agent_id = agent_id_marks_subagent(json::string(json.get("_source")), sources)
            .then(|| json::string(json.get("agent_id")).map(str::to_owned))
            .flatten();
        Some(Self {
            event_name,
            session_id,
            tool_name,
            tool_use_id,
            agent_id,
            tool_input,
            raw_json: json,
        })
    }

    /// `rawJSON[key]`.
    pub fn raw(&self, key: &str) -> Option<&Value> {
        self.raw_json.get(key)
    }

    fn is_codex_event(&self) -> bool {
        json::string(self.raw("_source")).is_some_and(|s| s.to_lowercase() == "codex")
    }

    /// `toolDescription`: what the tool is doing, for the card.
    pub fn tool_description(&self) -> Option<String> {
        if self.is_codex_event() {
            return self.codex_tool_description();
        }
        if let Some(description) = self
            .tool_input
            .as_ref()
            .and_then(|i| self.input_description(i))
        {
            return Some(description);
        }
        const TEXT_KEYS: &[&str] = &["message", "text", "summary", "status", "detail", "content"];
        first_string(&self.raw_json, TEXT_KEYS)
            .or_else(|| first_string_nested(&self.raw_json, &["payload", "data"], TEXT_KEYS))
            .or_else(|| json::string(self.raw("agent_type")).map(str::to_owned))
            .or_else(|| json::string(self.raw("prompt")).map(|p| json::prefix(p, 40)))
    }

    /// The `switch toolName` of `toolDescription`; `None` falls back to the
    /// payload's top-level text.
    fn input_description(&self, input: &JsonObject) -> Option<String> {
        let get = |key: &str| input.get(key);
        let either = |a: &str, b: &str| get(a).or_else(|| get(b));
        let file_name = |value: Option<&Value>| {
            json::string(value).map(|path| json::last_path_component(path).to_owned())
        };
        match self.tool_name.as_deref() {
            Some("Bash" | "execute_command" | "run_command") => {
                let desc = normalized_multiline(get("description"));
                let cmd = normalized_multiline(either("CommandLine", "command"));
                match (desc, cmd) {
                    (Some(desc), Some(cmd)) if desc == cmd || desc.contains(&cmd) => Some(desc),
                    (Some(desc), Some(cmd)) => Some(format!("{desc}\nCommand:\n{cmd}")),
                    (desc, cmd) => desc.or(cmd),
                }
            }
            Some("Read" | "read_file" | "view_file") => {
                let path = json::string(either("AbsolutePath", "file_path"))?;
                let name = json::last_path_component(path);
                if let (Some(start), Some(end)) =
                    (json::int(get("StartLine")), json::int(get("EndLine")))
                {
                    return Some(format!("{name}:{start}-{end}"));
                }
                if let Some(offset) = json::int(get("offset")) {
                    return Some(format!("{name}:{offset}"));
                }
                Some(name.to_owned())
            }
            Some(
                "Edit"
                | "apply_diff"
                | "replace_file_content"
                | "multi_replace_file_content"
                | "Write"
                | "write_to_file",
            ) => file_name(either("TargetFile", "file_path")),
            Some("Grep" | "search_files" | "grep_search") => {
                let pattern = json::string(either("Query", "pattern"))?;
                let path = json::string(either("SearchPath", "path"))
                    .map(|p| format!(" in {}", json::last_path_component(p)))
                    .unwrap_or_default();
                Some(format!("{pattern}{path}"))
            }
            Some("Glob") => json::string(get("pattern")).map(str::to_owned),
            Some("WebSearch") => json::string(get("query")).map(str::to_owned),
            Some("WebFetch") => {
                let url = json::string(get("url"))?;
                Some(url_host(url).map_or_else(|| json::prefix(url, 40), str::to_owned))
            }
            Some("Task" | "Agent") => json::non_empty(get("description"))
                .map(str::to_owned)
                .or_else(|| json::string(get("prompt")).map(|p| json::prefix(p, 40))),
            Some("TodoWrite") => Some("Updating tasks".to_owned()),
            _ => file_name(get("file_path"))
                .or_else(|| json::string(get("pattern")).map(str::to_owned))
                .or_else(|| json::string(get("command")).map(|c| json::prefix(c, 60)))
                .or_else(|| json::string(get("prompt")).map(|p| json::prefix(p, 40))),
        }
    }

    /// `activityLabel`: the tool's name, or for Codex a provider-neutral one.
    pub fn activity_label(&self) -> Option<String> {
        let tool_name = self.tool_name.as_deref()?;
        if !self.is_codex_event() {
            return Some(tool_name.to_owned());
        }
        let label = match self.activity_category() {
            ToolActivityCategory::Reading => "Reading",
            ToolActivityCategory::Searching => "Searching",
            ToolActivityCategory::Editing => "Editing",
            ToolActivityCategory::Shell => "Running command",
            ToolActivityCategory::Browser => "Using browser",
            ToolActivityCategory::Mcp => "Calling MCP",
            ToolActivityCategory::Delegation => "Delegating",
            ToolActivityCategory::Question => "Asking user",
            ToolActivityCategory::Other => return sanitized_summary(tool_name, 48),
        };
        Some(label.to_owned())
    }

    /// `activityCategory` (Codex only; `Other` for every other source).
    pub fn activity_category(&self) -> ToolActivityCategory {
        use ToolActivityCategory as C;
        let Some(raw) = self.tool_name.as_deref().filter(|_| self.is_codex_event()) else {
            return C::Other;
        };
        let name = raw.to_lowercase().replace('-', "_");
        let name = name.as_str();
        let has = |part: &str| name.contains(part);
        if name.starts_with("mcp__")
            || has("mcp_resource")
            || name == "list_mcp_resources"
            || name == "list_mcp_resource_templates"
        {
            C::Mcp
        } else if has("spawn_agent")
            || has("send_message")
            || has("followup_task")
            || has("wait_agent")
            || has("subagent")
            || name == "task"
            || name == "agent"
        {
            C::Delegation
        } else if has("request_user_input") || has("ask_user") {
            C::Question
        } else if has("browser")
            || has("playwright")
            || has("navigate")
            || name == "web_search"
            || name == "web_fetch"
        {
            C::Browser
        } else if has("apply_patch")
            || has("edit_file")
            || has("write_file")
            || has("delete_file")
            || has("move_file")
            || has("replace_file")
        {
            C::Editing
        } else if has("grep")
            || has("glob")
            || has("search")
            || name == "find"
            || name.starts_with("rg_")
        {
            C::Searching
        } else if has("read_file") || has("view_file") || has("view_image") || has("list_dir") {
            C::Reading
        } else if has("exec_command")
            || has("write_stdin")
            || has("shell")
            || name == "bash"
            || name == "command"
            || name == "run_command"
        {
            C::Shell
        } else {
            C::Other
        }
    }

    /// `codexToolDescription`.
    fn codex_tool_description(&self) -> Option<String> {
        use ToolActivityCategory as C;
        let empty = JsonObject::new();
        let input = self.tool_input.as_ref().unwrap_or(&empty);
        let category = self.activity_category();
        match category {
            C::Reading | C::Editing => {
                match first_string(
                    input,
                    &[
                        "file_path",
                        "path",
                        "filename",
                        "AbsolutePath",
                        "TargetFile",
                    ],
                ) {
                    Some(path) => sanitized_filename(&path),
                    None => (category == C::Editing).then(|| "Applying changes".to_owned()),
                }
            }
            C::Searching => first_string(input, &["query", "pattern", "Query"])
                .and_then(|q| sanitized_summary(&q, 80)),
            C::Shell => first_string(input, &["command", "cmd", "CommandLine"])
                .and_then(|c| sanitized_summary(&c, 120)),
            C::Browser => {
                let url = first_string(input, &["url", "uri"]);
                if let Some(host) = url.as_deref().and_then(url_host) {
                    return Some(host.to_owned());
                }
                first_string(input, &["query", "search_query"])
                    .and_then(|q| sanitized_summary(&q, 72))
            }
            C::Mcp => {
                let tool_name = self.tool_name.as_deref()?;
                let pieces: Vec<&str> = tool_name.split("__").filter(|p| !p.is_empty()).collect();
                (pieces.len() >= 3)
                    .then(|| sanitized_summary(&pieces[1..].join(" / "), 72))
                    .flatten()
            }
            C::Delegation => first_string(input, &["task_name", "description", "agent_type"])
                .and_then(|d| sanitized_summary(&d, 72)),
            C::Question => Some("Waiting for input".to_owned()),
            C::Other => {
                if let Some(path) = first_string(input, &["file_path", "path"]) {
                    return sanitized_filename(&path);
                }
                first_string(input, &["description", "summary"])
                    .and_then(|d| sanitized_summary(&d, 80))
            }
        }
    }
}

/// `HookEvent.cardSessionId(forRawSessionId:in:)`: remote hosts get a
/// namespace of their own, Codex Desktop hooks one `codexapp:` card.
pub fn card_session_id(raw_session_id: &str, json: &JsonObject) -> String {
    if let Some(host) = json::string(json.get("_remote_host_id")).filter(|h| !h.trim().is_empty()) {
        return format!("remote:{host}:{raw_session_id}");
    }
    let is_codex = json::string(json.get("_source")).is_some_and(|s| s.to_lowercase() == "codex");
    if is_codex && json::string(json.get("_term_bundle")) == Some("com.openai.codex") {
        return if raw_session_id.starts_with("codexapp:") {
            raw_session_id.to_owned()
        } else {
            format!("codexapp:{raw_session_id}")
        };
    }
    raw_session_id.to_owned()
}

/// `HookEvent.agentIdMarksSubagent(source:)`: TRAE stamps every hook with
/// its running agent's id, the main conversation's included.
fn agent_id_marks_subagent(source: Option<&str>, sources: &SourceCatalog) -> bool {
    !matches!(
        normalized_supported_source(source, sources).as_deref(),
        Some("trae" | "traecn")
    )
}

/// `HookEvent.firstString(in:keys:)`: the first non-blank string, trimmed.
fn first_string(dict: &JsonObject, keys: &[&str]) -> Option<String> {
    keys.iter()
        .find_map(|key| json::trimmed(dict.get(*key)))
        .map(str::to_owned)
}

/// `HookEvent.firstString(inNestedDictionary:containerKeys:keys:)`.
fn first_string_nested(dict: &JsonObject, containers: &[&str], keys: &[&str]) -> Option<String> {
    containers
        .iter()
        .find_map(|c| first_string(json::object(dict.get(*c))?, keys))
}

/// `HookEvent.firstDictionary(in:keys:)`.
fn first_object<'a>(dict: &'a JsonObject, keys: &[&str]) -> Option<&'a JsonObject> {
    keys.iter().find_map(|key| json::object(dict.get(*key)))
}

/// `HookEvent.normalizedMultilineString`.
fn normalized_multiline(value: Option<&Value>) -> Option<String> {
    json::trimmed(value).map(str::to_owned)
}

/// `URL(string:)?.host`, for an absolute `scheme://` URL. Swift's parser is
/// stricter; this one refuses whitespace and an empty host only.
fn url_host(url: &str) -> Option<&str> {
    if url.chars().any(char::is_whitespace) {
        return None;
    }
    let (_, rest) = url.split_once("://")?;
    let authority = rest.split(['/', '?', '#']).next()?;
    let host_port = authority.rsplit_once('@').map_or(authority, |(_, h)| h);
    let host = if host_port.starts_with('[') {
        host_port.split_inclusive(']').next()?
    } else {
        host_port.split(':').next()?
    };
    (!host.is_empty()).then_some(host)
}

/// `HookEvent.sanitizedFilename`.
fn sanitized_filename(path: &str) -> Option<String> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return None;
    }
    sanitized_summary(json::last_path_component(trimmed), 80)
}

/// `HookEvent.summaryRedactions`, verbatim (the `regex` crate reads these
/// ICU patterns the same way: no lookaround, no backreference).
static SUMMARY_REDACTIONS: LazyLock<Vec<(Regex, &'static str)>> = LazyLock::new(|| {
    [
        (r#"(?i)\b([a-z][a-z0-9+.-]*://)[^\s/@:"']+:[^\s/@"']+@"#, "$1[REDACTED]@"),
        (r#"(?i)(authorization\s*[:=]\s*(?:(?:bearer|basic|token|digest|negotiate|bot)\s+)?)([\"']?)[^\"'\s]+"#, "$1[REDACTED]"),
        (r#"(?i)((?:aws[-_]?secret[-_]?access[-_]?key|aws[-_]?(?:session|security)[-_]?token|x[-_]amz[-_]security[-_]token)\s*[:=]\s*)([\"']?)[^\"'\s]+"#, "$1[REDACTED]"),
        (r#"(?i)((?:x[-_])?(?:api[-_]?key|(?:auth|access|private|refresh|id|bearer|bot|deploy|session)[-_]?token|client[-_]?secret|secret|password|passwd)\s*:\s*)([\"']?)[^\"'\s]+"#, "$1[REDACTED]"),
        (r#"(?i)(["'][a-z0-9_.-]*?(?:api[-_]?key|apikey|token|secret|password|passwd|private[-_]?key|access[-_]?key|credentials?)["']\s*:\s*["'])[^"']*(["'])"#, "$1[REDACTED]$2"),
        (r#"(?i)((?:set-)?cookie\s*:\s*)[^"'\n]+"#, "$1[REDACTED]"),
        (r#"(?i)(\bcurl\b[^|;&]*?\s(?:-u\s*|--user(?:\s+|=)))(["']?)([^\s:"']*):[^\s"']+"#, "$1$2$3:[REDACTED]"),
        (r#"(?i)(\bcurl\b[^|;&]*?\s(?:-b|--cookie)(?:\s+|=))(["']?)[^\s"']+"#, "$1$2[REDACTED]"),
        (r#"(\bmysql\w*\b[^|;&]*?\s-p)([^\s"'-][^\s"']*)"#, "$1[REDACTED]"),
        (r#"(\bsshpass\b[^|;&]*?\s-p\s*)([^\s"']+)"#, "$1[REDACTED]"),
        (r#"(?i)(--(?:api[-_]?key|token|secret|password|passwd|auth|auth[-_]?token|access[-_]?token)(?:\s+|=))([\"']?)[^\s\"']+"#, "$1$2[REDACTED]"),
        (r#"(?i)((?:api[-_]?key|apikey|token|secret|password|passwd)=)([\"']?)[^\s\"'&]+"#, "$1$2[REDACTED]"),
        (r#"(?i)([?&](?:api[-_]?key|apikey|key|access[-_]?key|secret[-_]?key|token|access[-_]?token|auth[-_]?token|refresh[-_]?token|id[-_]?token|private[-_]?token|secret|client[-_]?secret|signature|sig|sign|password|passwd|auth)=)[^&\s\"'#]+"#, "$1[REDACTED]"),
        (r#"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|(?:AKIA|ASIA)[A-Z0-9]{16})\b"#, "[REDACTED]"),
        (r#"\b(?:glpat-[A-Za-z0-9_-]{20,}|xox[abposre]-[A-Za-z0-9-]{10,}|xapp-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|ya29\.[A-Za-z0-9_-]{20,}|npm_[A-Za-z0-9]{36}|hf_[A-Za-z0-9]{30,}|[rs]k_(?:live|test)_[A-Za-z0-9]{16,}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|pypi-[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,})"#, "[REDACTED]"),
        (r#"\b(?:bot)?\d{6,12}:[A-Za-z0-9_-]{30,}"#, "[REDACTED]"),
        (r#"/(?:Users|home)/[^/\s]+"#, "~"),
        (r#"\b[A-Za-z0-9_\-+/=]{48,}\b"#, "[REDACTED]"),
    ]
    .into_iter()
    .map(|(pattern, template)| (Regex::new(pattern).expect("redaction pattern"), template))
    .collect()
});

/// `HookEvent.sanitizedSummary(_:limit:)`: whitespace collapsed, credential
/// shapes and home-directory user names redacted, cut to `limit` chars.
pub fn sanitized_summary(value: &str, limit: usize) -> Option<String> {
    let mut result = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if result.is_empty() {
        return None;
    }
    for (regex, template) in SUMMARY_REDACTIONS.iter() {
        result = regex.replace_all(&result, *template).into_owned();
    }
    if result.chars().count() <= limit || limit <= 3 {
        return Some(result);
    }
    Some(format!("{}...", json::prefix(&result, limit - 3)))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn event(value: Value) -> HookEvent {
        HookEvent::new(
            value.as_object().unwrap().clone(),
            &SourceCatalog::default(),
        )
        .unwrap()
    }

    #[test]
    fn fields_are_read_like_swift() {
        let e = event(json!({
            "hook_event_name": " PreToolUse ", "session_id": "s", "_remote_host_id": "h",
            "tool": {"name": "Bash", "id": "t1"}, "agent_id": "", "_source": "claude"
        }));
        assert_eq!(e.event_name, "PreToolUse");
        assert_eq!(e.session_id.as_deref(), Some("remote:h:s"));
        assert_eq!(e.tool_name.as_deref(), Some("Bash"));
        assert_eq!(e.tool_use_id.as_deref(), Some("t1"));
        assert_eq!(e.agent_id.as_deref(), Some(""));
        let trae = event(json!({"hook_event_name": "Stop", "agent_id": "solo", "_source": "trae"}));
        assert_eq!(trae.agent_id, None);
        assert!(HookEvent::new(JsonObject::new(), &SourceCatalog::default()).is_none());
    }

    #[test]
    fn descriptions_and_codex_labels() {
        let bash = event(json!({"hook_event_name": "PreToolUse", "tool_name": "Bash",
            "tool_input": {"description": "List", "command": "ls -la"}}));
        assert_eq!(
            bash.tool_description().as_deref(),
            Some("List\nCommand:\nls -la")
        );
        let read = event(json!({"hook_event_name": "PreToolUse", "tool_name": "Read",
            "tool_input": {"file_path": "/a/b.rs", "offset": 3}}));
        assert_eq!(read.tool_description().as_deref(), Some("b.rs:3"));
        let codex = event(
            json!({"hook_event_name": "PreToolUse", "tool_name": "exec_command",
            "_source": "codex", "tool_input": {"cmd": "cat /Users/amal/x TOKEN=abc"}}),
        );
        assert_eq!(codex.activity_label().as_deref(), Some("Running command"));
        assert_eq!(
            codex.tool_description().as_deref(),
            Some("cat ~/x TOKEN=[REDACTED]")
        );
    }

    #[test]
    fn summaries_are_cut_and_hosts_read() {
        assert_eq!(sanitized_summary("  a \n b  ", 10).as_deref(), Some("a b"));
        assert_eq!(
            sanitized_summary("abcdefghij", 6).as_deref(),
            Some("abc...")
        );
        assert_eq!(sanitized_summary(" ", 6), None);
        assert_eq!(url_host("https://u:p@example.com:8/x"), Some("example.com"));
        assert_eq!(url_host("example.com/x"), None);
    }
}
