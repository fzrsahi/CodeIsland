//! What the bridge hands HookIntake (`morrow_core::intake`): its argv, the
//! environment and stdin, and what the OS says about its process, behind
//! [`ProcessFacts`] so tests hand in a fixture's process tree. The bridge
//! interprets nothing itself.

use std::collections::HashMap;

use morrow_core::intake::cursor_hook_payload::delivery_digest;
use morrow_core::intake::custom_agent_command::default_seeded_commands;
use morrow_core::intake::{
    Ancestor, ENVIRONMENT_KEYS, Facts, HookIntake, SourceCatalog, admits, stdin_object,
};

/// The bridge's argv: `--source` and `--event`, each the word after the
/// first occurrence of the flag, as the Swift bridge reads them.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Args {
    pub source: Option<String>,
    pub event: Option<String>,
}

impl Args {
    /// Reads the arguments after argv\[0\].
    pub fn parse<I: IntoIterator<Item = String>>(args: I) -> Self {
        let args: Vec<String> = args.into_iter().collect();
        let after = |flag: &str| {
            let index = args.iter().position(|a| a == flag)?;
            args.get(index + 1).cloned()
        };
        Self {
            source: after("--source"),
            event: after("--event"),
        }
    }
}

/// What the OS says about the hook's process. The calls that cost
/// something (a file read, a subprocess) are asked only when HookIntake
/// needs them.
pub trait ProcessFacts {
    /// The hook's parent process.
    fn parent_pid(&self) -> Option<i32>;
    /// Up to `MAX_ANCESTRY` processes from the parent up: pid and resolved
    /// executable, when readable.
    fn ancestry(&self) -> Vec<(i32, Option<String>)>;
    /// A process's argv, argv\[0\] included.
    fn arguments(&self, pid: i32) -> Vec<String>;
    /// The bundle id of the outermost `.app` holding an executable.
    fn bundle_identifier(&self, executable_path: &str) -> Option<String>;
    /// The directory the hook runs in.
    fn working_directory(&self) -> Option<String>;
    /// The hook's controlling terminal.
    fn tty(&self) -> Option<String>;
    /// The user's home directory.
    fn home_directory(&self) -> Option<String>;
    /// The tty of the tmux client showing `pane`.
    fn tmux_client_tty(&self, pane: &str) -> Option<String>;
    fn file_exists(&self, path: &str) -> bool;
}

/// `~` and `~/…` under `home` (`NSString.expandingTildeInPath`, without
/// its `~user` form).
pub fn expanding_tilde_in_path(path: &str, home: Option<&str>) -> String {
    match (home, path.strip_prefix('~')) {
        (Some(home), Some("")) => home.to_owned(),
        (Some(home), Some(rest)) if rest.starts_with('/') => format!("{home}{rest}"),
        _ => path.to_owned(),
    }
}

/// HookIntake's facts, as the Swift bridge gathers them: the environment
/// filtered to `ENVIRONMENT_KEYS`, the parent and the ancestry read once,
/// the rest asked when needed. The catalog is what Swift's
/// `CustomAgentCommandStore` holds for a process with no app preferences:
/// the seeded commands whose directory exists.
pub fn facts<'a>(
    args: &Args,
    environment: &HashMap<String, String>,
    stdin: &'a [u8],
    process: &'a dyn ProcessFacts,
) -> Facts<'a> {
    let home = process.home_directory();
    let custom_commands = home
        .as_deref()
        .map(|home| default_seeded_commands(home, |path| process.file_exists(path)))
        .unwrap_or_default();
    let tilde_home = home.clone();
    Facts {
        source_tag: args.source.clone(),
        event_tag: args.event.clone(),
        environment: environment
            .iter()
            .filter(|(key, _)| ENVIRONMENT_KEYS.contains(&key.as_str()))
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect(),
        parent_pid: process.parent_pid(),
        ancestry: process
            .ancestry()
            .into_iter()
            .map(|(pid, executable_path)| {
                let path = executable_path.clone();
                Ancestor::new(pid, executable_path)
                    .with_arguments(move || process.arguments(pid))
                    .with_bundle_identifier(move || {
                        path.as_deref().and_then(|p| process.bundle_identifier(p))
                    })
            })
            .collect(),
        working_directory: Box::new(move || process.working_directory()),
        tty: Box::new(move || process.tty()),
        home_directory: Box::new(move || home.clone()),
        expanding_tilde_in_path: Box::new(move |path| {
            expanding_tilde_in_path(path, tilde_home.as_deref())
        }),
        stdin_digest: Box::new(move || Some(delivery_digest(stdin))),
        tmux_client_tty: Box::new(move |pane| process.tmux_client_tty(pane)),
        file_exists: Box::new(move |path| process.file_exists(path)),
        catalog: SourceCatalog {
            custom_sources: Vec::new(),
            custom_commands,
        },
        ..Facts::default()
    }
}

/// One invocation, interpreted without the transport. `None`: the hook is
/// dropped (not admitted, stdin empty or not a JSON object, no session),
/// exit 0.
pub fn interpret<'a>(
    args: &Args,
    environment: &HashMap<String, String>,
    stdin: &'a [u8],
    process: &'a dyn ProcessFacts,
) -> Option<HookIntake<'a>> {
    if !admits(args.source.as_deref(), environment) || stdin.is_empty() {
        return None;
    }
    let object = stdin_object(stdin, args.source.as_deref())?;
    HookIntake::new(object, facts(args, environment, stdin, process))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn args_take_the_word_after_the_first_flag() {
        let args = Args::parse(
            ["--source", "codex", "--event", "Stop", "--source", "x"].map(String::from),
        );
        assert_eq!(args.source.as_deref(), Some("codex"));
        assert_eq!(args.event.as_deref(), Some("Stop"));
        assert_eq!(Args::parse(["--source".to_owned()]), Args::default());
    }

    #[test]
    fn tilde_expands_under_home_only() {
        let home = Some("/home/dev");
        assert_eq!(expanding_tilde_in_path("~", home), "/home/dev");
        assert_eq!(
            expanding_tilde_in_path("~/.hermes", home),
            "/home/dev/.hermes"
        );
        assert_eq!(expanding_tilde_in_path("~bob/x", home), "~bob/x");
        assert_eq!(expanding_tilde_in_path("/abs", home), "/abs");
        assert_eq!(expanding_tilde_in_path("~/x", None), "~/x");
    }
}
