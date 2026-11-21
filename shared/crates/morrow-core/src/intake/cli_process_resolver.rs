//! Which process belongs to which agent (`CLIProcessResolver` in
//! `macos/Sources/MorrowCore/Models.swift`): matching an executable path to a
//! source, inferring the source from the ancestry, and the pid the island
//! tracks. The ancestry is HookIntake's [`Ancestor`] list, nearest first.

use super::host_harness::{deleting_last_path_component, outermost_app_bundle_path, standardized};
use super::session_snapshot::{
    IDE_HOST_SOURCES, SUPPORTED_SOURCES, SourceCatalog, normalized_supported_source,
};
use super::{Ancestor, cursor_hook_payload};

/// Lowercased bundle markers of the Trae CN desktop IDE (`cn.trae.app`):
/// `Trae CN.app`, `TraeCode CN.app`, `TraeCN.app`. None of them matches the
/// international `Trae.app`.
pub const TRAE_CN_BUNDLE_PATH_MARKERS: &[&str] = &[
    "/trae cn.app/contents/",
    "/traecode cn.app/contents/",
    "/traecn.app/contents/",
];

/// `isTraeCNBundlePath`.
pub fn is_trae_cn_bundle_path(path: &str) -> bool {
    let lower = path.to_lowercase();
    TRAE_CN_BUNDLE_PATH_MARKERS
        .iter()
        .any(|m| lower.contains(m))
}

/// `isMimoCLIPath`: the MiMo Code CLI however it was installed, never the
/// Xiaomi MiMo desktop app (it has an integrated terminal: claiming it
/// would pin any agent started there on MiMo).
pub fn is_mimo_cli_path(path: &str) -> bool {
    let lower = path.to_lowercase();
    let basename = last_path_component(&lower);
    basename == "mimo"
        || (basename == ".mimocode" && lower.contains("/@mimo-ai/cli/"))
        || lower.contains("/@mimo-ai/mimocode-")
}

/// Lowercased bundle markers of the Xiaomi MiMo desktop app.
pub const MIMO_DESKTOP_BUNDLE_PATH_MARKERS: &[&str] = &[
    "/xiaomi mimo.app/contents/",
    "/xiaomi mimo ai.app/contents/",
];

/// `isMimoDesktopBundlePath`.
pub fn is_mimo_desktop_bundle_path(path: &str) -> bool {
    let lower = path.to_lowercase();
    MIMO_DESKTOP_BUNDLE_PATH_MARKERS
        .iter()
        .any(|m| lower.contains(m))
}

/// `(path as NSString).lastPathComponent`.
fn last_path_component(path: &str) -> &str {
    let trimmed = path.trim_end_matches('/');
    if trimmed.is_empty() {
        return if path.is_empty() { "" } else { "/" };
    }
    trimmed.rsplit('/').next().unwrap_or(trimmed)
}

/// `sourceMatchesExecutablePath(_:source:)`: whether the executable at
/// `path` is `source`'s agent.
pub fn source_matches_executable_path(
    path: &str,
    source: Option<&str>,
    catalog: &SourceCatalog,
) -> bool {
    let Some(normalized_source) = normalized_supported_source(source, catalog) else {
        return false;
    };
    let path = path.to_lowercase();
    let basename = || last_path_component(&path);

    match normalized_source.as_str() {
        // Trae CN runs hooks through `bash -c`: the bundle, not the shell.
        "traecn" => is_trae_cn_bundle_path(&path),
        "traecli" => {
            path.ends_with("/coco")
                || path.ends_with("/traecli")
                || path.contains("/coco ")
                || path.contains("/traecli ")
        }
        "codex" => {
            path.ends_with("/codex")
                || path.contains("/codex ")
                || catalog.matches_custom_command(&path, "codex")
        }
        // The native installer runs the binary named by its version:
        // ~/.local/share/claude/versions/2.1.294.
        "claude" => {
            path.ends_with("/claude")
                || path.contains("/claude ")
                || path.contains("/.local/share/claude/versions/")
                || catalog.matches_custom_command(&path, "claude")
        }
        "dsh" => path.ends_with("/dsh") || path.contains("/dsh "),
        "qwen" => {
            path.ends_with("/qwen")
                || path.ends_with("/qwen-code")
                || path.contains("/qwen ")
                || path.contains("/qwen-code ")
        }
        "gemini" => path.ends_with("/gemini") || path.contains("/gemini "),
        // Managed installs run the versioned binary from $GROK_HOME/downloads.
        "grok" => {
            let basename = basename();
            basename == "grok"
                || (basename.starts_with("grok-")
                    && (path.contains("/.grok/downloads/") || path.contains("/grok/downloads/")))
        }
        // ~/.local/share/cursor-agent/versions/<v>/cursor-agent, or
        // /cursor-agent/index.js under Node.
        "cursor-cli" => path.contains("/cursor-agent"),
        // qodercli, and the China build's qoderclicn (versioned) (#289).
        "qoder-cli" => {
            let basename = basename();
            path.ends_with("/qodercli")
                || path.contains("/qodercli ")
                || path.contains("/@qoder-ai/qodercli")
                || basename == "qoderclicn"
                || basename.starts_with("qoderclicn-")
                || path.contains("/qoderclicn/")
                || path.contains("/.qoder-cn/")
        }
        "google-antigravity" => {
            path.ends_with("/agy") || path.contains("/agy ") || path.contains("/google-antigravity")
        }
        // `mcode`; Node renames the process title to `minimax-code`.
        "minimax" => {
            let basename = basename();
            basename == "mcode" || basename == "minimax-code" || path.contains("/@minimax-ai/code/")
        }
        "mimo" => is_mimo_cli_path(&path),
        // By name: as a substring "/pi" is also pinentry, pip, /Users/pierre.
        "pi" => {
            let basename = basename();
            basename == "pi" || basename == "omp" || path.contains("/pi-coding-agent/")
        }
        other => path.contains(&format!("/{other}")),
    }
}

/// `cliVariantOverride(declaredSource:ancestry:)`: `cursor` under
/// cursor-agent is `cursor-cli`, `qoder` under qodercli is `qoder-cli`
/// (the CLI and the IDE share one hooks file, #134).
pub fn cli_variant_override(
    declared_source: Option<&str>,
    ancestry: &[Ancestor<'_>],
    catalog: &SourceCatalog,
) -> Option<&'static str> {
    let under = |variant: &str| {
        ancestry.iter().any(|a| {
            source_matches_executable_path(
                a.executable_path.as_deref().unwrap_or(""),
                Some(variant),
                catalog,
            )
        })
    };
    match normalized_supported_source(declared_source, catalog)?.as_str() {
        "cursor" if under("cursor-cli") => Some("cursor-cli"),
        "qoder" if under("qoder-cli") => Some("qoder-cli"),
        _ => None,
    }
}

/// What [`bridge_source`] decides.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BridgeSource {
    pub source: Option<String>,
    /// The event came through another agent's hook (`_via_plugin`).
    pub via_plugin: bool,
}

/// `bridgeSource(sourceTag:payloadSource:cursorPayload:ancestry:)`.
///
/// Declared: `--source`, else a supported `_source` in the payload (a
/// direct plugin), else Cursor's payload. Only an undeclared event is
/// attributed by ancestry, and marked as proxied unless the ancestry says
/// Claude (Claude Code firing its own source-less hook is no proxy).
pub fn bridge_source(
    source_tag: Option<&str>,
    payload_source: Option<&str>,
    cursor_payload: bool,
    ancestry: &[Ancestor<'_>],
    catalog: &SourceCatalog,
) -> BridgeSource {
    let declared: Option<String> = source_tag
        .map(str::to_owned)
        .or_else(|| normalized_supported_source(payload_source, catalog))
        .or_else(|| cursor_payload.then(|| cursor_hook_payload::SOURCE.to_owned()));
    let inferred = declared
        .clone()
        .or_else(|| infer_source(ancestry, catalog).map(str::to_owned));
    let effective = cli_variant_override(inferred.as_deref(), ancestry, catalog)
        .map(str::to_owned)
        .or(inferred);
    let via_plugin = declared.is_none() && effective.as_deref().is_some_and(|s| s != "claude");
    BridgeSource {
        source: effective,
        via_plugin,
    }
}

/// `resolvedTrackedPID`: the nearest ancestor that is `source`'s agent,
/// else the immediate parent.
pub fn resolved_tracked_pid(
    immediate_parent_pid: i32,
    source: Option<&str>,
    ancestry: &[Ancestor<'_>],
    catalog: &SourceCatalog,
) -> i32 {
    if immediate_parent_pid <= 0 {
        return immediate_parent_pid;
    }
    ancestry
        .iter()
        .find(|a| {
            source_matches_executable_path(
                a.executable_path.as_deref().unwrap_or(""),
                source,
                catalog,
            )
        })
        .map_or(immediate_parent_pid, |a| a.pid)
}

/// `resolvedSessionPID`: the farthest ancestor that is `source`'s agent,
/// else the immediate parent, so the sub-agents of one CLI share one
/// fallback session (#148).
pub fn resolved_session_pid(
    immediate_parent_pid: i32,
    source: Option<&str>,
    ancestry: &[Ancestor<'_>],
    catalog: &SourceCatalog,
) -> i32 {
    if immediate_parent_pid <= 0 {
        return immediate_parent_pid;
    }
    ancestry
        .iter()
        .rev()
        .find(|a| {
            source_matches_executable_path(
                a.executable_path.as_deref().unwrap_or(""),
                source,
                catalog,
            )
        })
        .map_or(immediate_parent_pid, |a| a.pid)
}

/// `codexDesktopTermBundle(ancestry:)`: `com.openai.codex` for a hook of
/// Codex Desktop's app-server, which ChatGPT starts without
/// `__CFBundleIdentifier`. The nearest Codex process must run `app-server`,
/// and its parent must be an executable in the app's own `Contents/MacOS`
/// whose bundle is `com.openai.codex`. Only the arguments and bundle id
/// those two need are asked for.
pub fn codex_desktop_term_bundle(
    ancestry: &[Ancestor<'_>],
    catalog: &SourceCatalog,
) -> Option<&'static str> {
    let codex_index = ancestry.iter().position(|a| {
        source_matches_executable_path(
            a.executable_path.as_deref().unwrap_or(""),
            Some("codex"),
            catalog,
        )
    })?;
    if !is_codex_app_server_invocation(&(ancestry[codex_index].arguments)()) {
        return None;
    }
    let parent = ancestry.get(codex_index + 1)?;
    if (parent.bundle_identifier)().as_deref() != Some("com.openai.codex") {
        return None;
    }
    let parent_path = parent.executable_path.as_deref()?;
    let app_path = outermost_app_bundle_path(parent_path)?;
    let parent_dir = deleting_last_path_component(&standardized(parent_path));
    let app_macos = standardized(&format!("{app_path}/Contents/MacOS"));
    (parent_dir == app_macos).then_some("com.openai.codex")
}

/// `isCodexAppServerInvocation`.
pub fn is_codex_app_server_invocation(arguments: &[String]) -> bool {
    codex_subcommand(arguments) == Some("app-server")
}

/// `codexSubcommand`: the first word after `codex [-c key=value]…`, or
/// `None` when argv\[0\] is not `codex` or that word is an option.
pub fn codex_subcommand(arguments: &[String]) -> Option<&str> {
    let program = arguments.first()?;
    if last_path_component(program) != "codex" {
        return None;
    }
    let mut index = 1;
    while index < arguments.len() && (arguments[index] == "-c" || arguments[index] == "--config") {
        index += 2;
    }
    let word = arguments.get(index)?;
    (!word.starts_with('-')).then_some(word.as_str())
}

/// `inferSource(ancestry:)`: the first supported source whose binary is in
/// the ancestry, nearest process first; `-cli` variants first (#134), and
/// never a desktop-IDE host (#220).
pub fn infer_source(ancestry: &[Ancestor<'_>], catalog: &SourceCatalog) -> Option<&'static str> {
    let candidates: Vec<&'static str> = SUPPORTED_SOURCES
        .iter()
        .copied()
        .filter(|s| !IDE_HOST_SOURCES.contains(s))
        .collect();
    let mut cli: Vec<&'static str> = candidates
        .iter()
        .copied()
        .filter(|s| s.ends_with("-cli"))
        .collect();
    let mut rest: Vec<&'static str> = candidates
        .into_iter()
        .filter(|s| !s.ends_with("-cli"))
        .collect();
    cli.sort_unstable();
    rest.sort_unstable();
    let cli_first: Vec<&'static str> = cli.into_iter().chain(rest).collect();

    ancestry
        .iter()
        .filter_map(|a| a.executable_path.as_deref())
        .filter(|path| !path.is_empty())
        .find_map(|path| {
            cli_first
                .iter()
                .copied()
                .find(|source| source_matches_executable_path(path, Some(source), catalog))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn matches(path: &str, source: &str) -> bool {
        source_matches_executable_path(path, Some(source), &SourceCatalog::default())
    }

    fn chain(paths: &[&str]) -> Vec<Ancestor<'static>> {
        paths
            .iter()
            .enumerate()
            .map(|(i, p)| Ancestor::new(100 + i as i32, Some((*p).to_owned())))
            .collect()
    }

    #[test]
    fn per_source_path_rules() {
        assert!(matches(
            "/home/dev/.local/share/claude/versions/2.1.294",
            "claude"
        ));
        assert!(matches("/opt/homebrew/bin/claude", "claude"));
        assert!(!matches("/usr/local/bin/node", "claude"));
        assert!(matches(
            "/home/dev/.grok/downloads/grok-0.2.106-macos-aarch64",
            "grok"
        ));
        assert!(!matches("/usr/bin/grok-tool", "grok"));
        assert!(matches(
            "/home/dev/.qoder-cn/bin/qoderclicn-1.1.5",
            "qoder-cli"
        ));
        assert!(matches(
            "/Applications/Trae CN.app/Contents/MacOS/Electron",
            "traecn"
        ));
        assert!(!matches(
            "/Applications/Trae.app/Contents/MacOS/Electron",
            "traecn"
        ));
        assert!(matches("/usr/local/bin/pi", "pi"));
        assert!(!matches("/Users/pierre/bin/tool", "pi"));
        assert!(matches("/x/@minimax-ai/code/bin/minimax-code", "minimax"));
        assert!(matches("/home/dev/.mimocode/bin/mimo", "mimo"));
        assert!(matches("/home/dev/.local/bin/coco", "traecli"));
    }

    #[test]
    fn inference_prefers_cli_variants_and_skips_ide_hosts() {
        let catalog = SourceCatalog::default();
        let cursor_agent = chain(&["/home/dev/.local/share/cursor-agent/versions/1/cursor-agent"]);
        assert_eq!(infer_source(&cursor_agent, &catalog), Some("cursor-cli"));
        let in_cursor = chain(&[
            "/usr/bin/node",
            "/Applications/Cursor.app/Contents/MacOS/Cursor",
        ]);
        assert_eq!(infer_source(&in_cursor, &catalog), None);
        assert_eq!(
            cli_variant_override(
                Some("qoder"),
                &chain(&["/opt/homebrew/bin/qodercli"]),
                &catalog
            ),
            Some("qoder-cli")
        );
    }

    #[test]
    fn codex_subcommand_skips_config_pairs() {
        let argv = |a: &[&str]| a.iter().map(|s| (*s).to_owned()).collect::<Vec<_>>();
        assert_eq!(
            codex_subcommand(&argv(&["/x/codex", "-c", "a=b", "app-server"])),
            Some("app-server")
        );
        assert_eq!(
            codex_subcommand(&argv(&["/x/codex", "--", "app-server"])),
            None
        );
        assert_eq!(codex_subcommand(&argv(&["/x/node", "app-server"])), None);
    }
}
