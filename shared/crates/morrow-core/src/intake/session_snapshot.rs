//! Source names (`SessionSnapshot.supportedSources`, `ideHostSources` and
//! `normalizedSupportedSource` in `Sources/MorrowCore/SessionSnapshot.swift`).
//!
//! Swift reads the custom sources and custom agent commands from
//! `UserDefaults`; here they come in as a [`SourceCatalog`].

use super::custom_agent_command::CustomAgentCommand;

/// `SessionSnapshot.supportedSources`.
pub const SUPPORTED_SOURCES: &[&str] = &[
    "claude",
    "codex",
    "gemini",
    "cursor",
    "cursor-cli",
    "trae",
    "traecn",
    "traecli",
    "copilot",
    "qoder",
    "qoder-cli",
    "qoderwork",
    "droid",
    "codebuddy",
    "codybuddycn",
    "stepfun",
    "opencode",
    // MiMo Code (Xiaomi's OpenCode 1.x fork) and the Xiaomi MiMo desktop
    // app, which runs MiMo Code as its engine: one plugin feeds both.
    "mimo",
    "antigravity",
    "google-antigravity",
    "workbuddy",
    "hermes",
    "grok",
    "openclaw",
    "qwen",
    "kimi",
    "pi",
    "kiro",
    "cline",
    "dsh",
    "zcode",
    "aiwork",
    "aiwork-cli",
    "minimax",
];

/// `SessionSnapshot.ideHostSources`: desktop-IDE hosts, whose GUI processes
/// sit above any CLI run in the IDE's terminal. Never inferred from the
/// ancestry (#220): an IDE always reports itself through `--source`.
pub const IDE_HOST_SOURCES: &[&str] = &[
    "cursor",
    "trae",
    "traecn",
    "qoder",
    "codebuddy",
    "codybuddycn",
    "stepfun",
    "antigravity",
    "google-antigravity",
];

/// The aliases of `normalizedSupportedSource`, verbatim.
const ALIASES: &[(&str, &str)] = &[
    ("factory", "droid"),
    ("ag", "antigravity"),
    ("anti-gravity", "antigravity"),
    ("anti gravity", "antigravity"),
    // Google Antigravity (Gemini-based IDE/CLI): a separate product from
    // the "antigravity" Claude Code fork above (#215).
    ("googleantigravity", "google-antigravity"),
    ("google antigravity", "google-antigravity"),
    ("google-anti-gravity", "google-antigravity"),
    ("antigravity-ide", "google-antigravity"),
    ("antigravity-cli", "google-antigravity"),
    ("agy", "google-antigravity"),
    ("work-buddy", "workbuddy"),
    ("work body", "workbuddy"),
    ("work-body", "workbuddy"),
    ("workbody", "workbuddy"),
    ("hermes-agent", "hermes"),
    ("hermes-agents", "hermes"),
    ("hermes agent", "hermes"),
    ("hermes agents", "hermes"),
    ("grok-cli", "grok"),
    ("grokcli", "grok"),
    ("grok-build", "grok"),
    ("grok build", "grok"),
    ("open-claw", "openclaw"),
    ("open claw", "openclaw"),
    ("clawdbot", "openclaw"),
    ("qwen-code", "qwen"),
    ("qwencode", "qwen"),
    ("cursor-agent", "cursor-cli"),
    ("cursoragent", "cursor-cli"),
    ("cursorcli", "cursor-cli"),
    ("qodercli", "qoder-cli"),
    // Qoder China build: a separate `qoderclicn` binary, same contract (#289).
    ("qoderclicn", "qoder-cli"),
    ("qodercli-cn", "qoder-cli"),
    ("qoder-cn", "qoder-cli"),
    ("dtcoder", "aiwork"),
    ("dtcoder-cli", "aiwork-cli"),
    ("dtcodercli", "aiwork-cli"),
    ("aiworkcli", "aiwork-cli"),
    ("qodercn", "qoder-cli"),
    ("qoder-work", "qoderwork"),
    ("qoder work", "qoderwork"),
    ("kimi-cli", "kimi"),
    ("kimicli", "kimi"),
    ("kimi-code", "kimi"),
    ("kimicode", "kimi"),
    ("kimi_code", "kimi"),
    ("kimi-code-cli", "kimi"),
    ("kimicodecli", "kimi"),
    ("kimi_code_cli", "kimi"),
    ("kiro-cli", "kiro"),
    ("kirocli", "kiro"),
    ("codebuddycn", "codybuddycn"),
    ("codybuddy-cn", "codybuddycn"),
    ("step-fun", "stepfun"),
    ("step fun", "stepfun"),
    ("trae-cn", "traecn"),
    ("trae_cn", "traecn"),
    ("trae cn", "traecn"),
    ("traecli", "traecli"),
    ("omp", "pi"),
    ("oh-my-pi", "pi"),
    ("oh my pi", "pi"),
    ("z-code", "zcode"),
    ("z code", "zcode"),
    ("mcode", "minimax"),
    ("minimax-code", "minimax"),
    ("minimaxcode", "minimax"),
    ("minimax-cli", "minimax"),
    ("minimaxcli", "minimax"),
    ("minimax-code-cli", "minimax"),
    // No prefix rule for MiMo: "mimo…" is too short a stem to claim.
    ("mimocode", "mimo"),
    ("mimo-code", "mimo"),
    ("mimo_code", "mimo"),
    ("mimo code", "mimo"),
    ("mimo-cli", "mimo"),
    ("mimocli", "mimo"),
    ("mimo-desktop", "mimo"),
    ("mimodesktop", "mimo"),
    ("xiaomi-mimo", "mimo"),
    ("xiaomimimo", "mimo"),
    ("xiaomi mimo", "mimo"),
    ("xiaomi-mimo-ai", "mimo"),
];

/// The prefix rules applied after the alias table, in Swift's order:
/// Google Antigravity before the bare `antigravity` fork.
const PREFIXES: &[(&[&str], &str)] = &[
    (
        &["google-antigravity", "googleantigravity"],
        "google-antigravity",
    ),
    (&["antigravity"], "antigravity"),
    (&["workbuddy"], "workbuddy"),
    (&["hermes"], "hermes"),
    (&["grok"], "grok"),
    (&["openclaw"], "openclaw"),
    (&["qwen"], "qwen"),
    (&["kiro"], "kiro"),
    (&["kimi"], "kimi"),
    (&["minimax"], "minimax"),
    (&["codybuddycn", "codebuddycn"], "codybuddycn"),
    (&["stepfun"], "stepfun"),
    (&["traecn"], "traecn"),
    (&["traecli"], "traecli"),
    (&["trae"], "trae"),
];

/// What Swift reads from `UserDefaults` while it interprets a hook: the
/// app's custom CLI sources (`custom_cli_configs_v1`) and custom agent
/// commands (`CustomAgentCommandStore.loadCommands()`). Empty by default.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SourceCatalog {
    /// Custom CLI sources (`SessionSnapshot.loadCustomSources`), as the
    /// user wrote them: matched trimmed and lowercased.
    pub custom_sources: Vec<String>,
    /// Custom agent commands, `claude-govtech` and the like.
    pub custom_commands: Vec<CustomAgentCommand>,
}

impl SourceCatalog {
    fn is_custom_source(&self, canonical: &str) -> bool {
        self.custom_sources
            .iter()
            .map(|source| source.trim().to_lowercase())
            .any(|source| !source.is_empty() && source == canonical)
    }
}

/// `SessionSnapshot.normalizedSupportedSource`: the supported source
/// `source` names, after custom commands, aliases and prefixes; `None` for a
/// blank or unknown one.
pub fn normalized_supported_source(
    source: Option<&str>,
    catalog: &SourceCatalog,
) -> Option<String> {
    let normalized = source?.trim().to_lowercase();
    if normalized.is_empty() {
        return None;
    }
    if let Some(custom_agent) = catalog.canonical_agent(&normalized) {
        return Some(custom_agent);
    }
    let canonical = ALIASES
        .iter()
        .find(|(alias, _)| *alias == normalized)
        .map_or(normalized.as_str(), |(_, to)| to);
    if SUPPORTED_SOURCES.contains(&canonical) || catalog.is_custom_source(canonical) {
        return Some(canonical.to_owned());
    }
    PREFIXES
        .iter()
        .find(|(prefixes, _)| prefixes.iter().any(|p| canonical.starts_with(p)))
        .map(|(_, to)| (*to).to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn normalized(source: &str) -> Option<String> {
        normalized_supported_source(Some(source), &SourceCatalog::default())
    }

    #[test]
    fn aliases_and_prefixes_normalize_like_swift() {
        assert_eq!(normalized(" Claude ").as_deref(), Some("claude"));
        assert_eq!(normalized("Anti-Gravity").as_deref(), Some("antigravity"));
        assert_eq!(normalized("agy").as_deref(), Some("google-antigravity"));
        assert_eq!(
            normalized("google-antigravity-beta").as_deref(),
            Some("google-antigravity")
        );
        assert_eq!(normalized("cursor-agent").as_deref(), Some("cursor-cli"));
        assert_eq!(normalized("hermes-nightly").as_deref(), Some("hermes"));
        assert_eq!(normalized("not-a-real-agent"), None);
        assert_eq!(normalized("  "), None);
        assert_eq!(
            normalized_supported_source(None, &SourceCatalog::default()),
            None
        );
    }

    #[test]
    fn the_catalog_adds_custom_sources_and_commands() {
        let catalog = SourceCatalog {
            custom_sources: vec![" MyCLI ".into()],
            custom_commands: vec![CustomAgentCommand::new("claude-govtech", "claude")],
        };
        let normalized = |s| normalized_supported_source(Some(s), &catalog);
        assert_eq!(normalized("mycli").as_deref(), Some("mycli"));
        assert_eq!(normalized("Claude-GovTech").as_deref(), Some("claude"));
        assert_eq!(
            normalized_supported_source(Some("mycli"), &SourceCatalog::default()),
            None
        );
    }
}
