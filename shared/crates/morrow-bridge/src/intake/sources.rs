//! Source names and which process belongs to a source
//! (`SessionSnapshot.normalizedSupportedSource`, `CLIProcessResolver` in
//! `Sources/MorrowCore`).
//!
//! TODO(#93): moves to morrow-core HookIntake, with every per-source path
//! rule of `CLIProcessResolver.sourceMatchesExecutablePath` and ancestry
//! inference for every source. This ticket (#89) serves Claude Code's hook:
//! only the `claude` and `cursor-cli` path rules are ported; any other
//! source falls back to Swift's default rule (`/<source>` in the path).

use crate::intake::Ancestor;

/// `SessionSnapshot.supportedSources`. Custom CLI sources (the app's
/// settings) are not known to the bridge.
const SUPPORTED: &[&str] = &[
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

/// The aliases of `SessionSnapshot.normalizedSupportedSource`, verbatim.
const ALIASES: &[(&str, &str)] = &[
    ("factory", "droid"),
    ("ag", "antigravity"),
    ("anti-gravity", "antigravity"),
    ("anti gravity", "antigravity"),
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

/// Prefix rules applied after the alias table, in Swift's order.
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

/// The supported source `source` names, after aliases; `None` for a blank
/// or unknown one.
pub fn normalized_supported_source(source: Option<&str>) -> Option<&'static str> {
    let normalized = source?.trim().to_lowercase();
    if normalized.is_empty() {
        return None;
    }
    let canonical = ALIASES
        .iter()
        .find(|(alias, _)| *alias == normalized)
        .map_or(normalized.as_str(), |(_, to)| to);
    if let Some(known) = SUPPORTED.iter().find(|known| **known == canonical) {
        return Some(known);
    }
    PREFIXES
        .iter()
        .find(|(prefixes, _)| prefixes.iter().any(|p| canonical.starts_with(p)))
        .map(|(_, to)| *to)
}

/// Whether the executable at `path` is `source`'s agent.
pub fn source_matches_executable_path(path: &str, source: Option<&str>) -> bool {
    let Some(source) = normalized_supported_source(source) else {
        return false;
    };
    let path = path.to_lowercase();
    match source {
        // The native installer runs the binary named by its version:
        // ~/.local/share/claude/versions/2.1.294.
        "claude" => {
            path.ends_with("/claude")
                || path.contains("/claude ")
                || path.contains("/.local/share/claude/versions/")
        }
        // ~/.local/share/cursor-agent/versions/<v>/cursor-agent.
        "cursor-cli" => path.contains("/cursor-agent"),
        // TODO(#93): the other per-source rules of CLIProcessResolver.
        other => path.contains(&format!("/{other}")),
    }
}

/// The source the ancestry shows, nearest process first.
///
/// TODO(#93): Swift tries every supported source but the desktop-IDE hosts
/// (`-cli` variants first) on each ancestor; only Claude Code is inferred
/// here, so another agent firing Claude Code's hook (omo under OpenCode) is
/// not recognised and the event goes out with no `_source`.
pub fn infer_source(ancestry: &[Ancestor]) -> Option<&'static str> {
    ancestry
        .iter()
        .filter_map(|a| a.executable_path.as_deref())
        .filter(|path| !path.is_empty())
        .find(|path| source_matches_executable_path(path, Some("claude")))
        .map(|_| "claude")
}

/// `CLIProcessResolver.cliVariantOverride`: `cursor` under cursor-agent is
/// `cursor-cli`. TODO(#93): `qoder` under qodercli is `qoder-cli`.
pub fn cli_variant_override(declared: Option<&str>, ancestry: &[Ancestor]) -> Option<&'static str> {
    let under_cursor_agent = || {
        ancestry.iter().any(|a| {
            source_matches_executable_path(
                a.executable_path.as_deref().unwrap_or(""),
                Some("cursor-cli"),
            )
        })
    };
    (normalized_supported_source(declared) == Some("cursor") && under_cursor_agent())
        .then_some("cursor-cli")
}

/// `CLIProcessResolver.resolvedTrackedPID`: the nearest ancestor that is
/// `source`'s agent, else the immediate parent.
pub fn resolved_tracked_pid(parent: i32, source: Option<&str>, ancestry: &[Ancestor]) -> i32 {
    if parent <= 0 {
        return parent;
    }
    ancestry
        .iter()
        .find(|a| {
            source_matches_executable_path(a.executable_path.as_deref().unwrap_or(""), source)
        })
        .map_or(parent, |a| a.pid)
}

/// `CLIProcessResolver.resolvedSessionPID`: the farthest ancestor that is
/// `source`'s agent, else the immediate parent.
pub fn resolved_session_pid(parent: i32, source: Option<&str>, ancestry: &[Ancestor]) -> i32 {
    if parent <= 0 {
        return parent;
    }
    ancestry
        .iter()
        .rev()
        .find(|a| {
            source_matches_executable_path(a.executable_path.as_deref().unwrap_or(""), source)
        })
        .map_or(parent, |a| a.pid)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aliases_and_prefixes_normalize_like_swift() {
        assert_eq!(
            normalized_supported_source(Some(" Claude ")),
            Some("claude")
        );
        assert_eq!(
            normalized_supported_source(Some("Anti-Gravity")),
            Some("antigravity")
        );
        assert_eq!(
            normalized_supported_source(Some("cursor-agent")),
            Some("cursor-cli")
        );
        assert_eq!(
            normalized_supported_source(Some("hermes-nightly")),
            Some("hermes")
        );
        assert_eq!(normalized_supported_source(Some("not-a-real-agent")), None);
        assert_eq!(normalized_supported_source(Some("  ")), None);
        assert_eq!(normalized_supported_source(None), None);
    }

    #[test]
    fn claude_path_rule() {
        for path in [
            "/opt/homebrew/bin/claude",
            "/home/dev/.local/share/claude/versions/2.1.294",
            "/Applications/Claude.app/Contents/Resources/app/claude-code/claude",
        ] {
            assert!(
                source_matches_executable_path(path, Some("claude")),
                "{path}"
            );
        }
        assert!(!source_matches_executable_path(
            "/usr/local/bin/node",
            Some("claude")
        ));
    }
}
