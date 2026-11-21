//! Custom agent commands (`Sources/MorrowCore/CustomAgentCommand.swift`):
//! the parts HookIntake reads, over a [`SourceCatalog`] instead of
//! `UserDefaults`.

use super::session_snapshot::SourceCatalog;

/// `CustomAgentCommand`: a command that runs an agent under another name
/// (`claude-govtech` for Claude Code). Only the fields intake reads.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CustomAgentCommand {
    /// The executable's name, `claude-govtech`.
    pub command: String,
    /// The agent it runs: `claude`, `codex`, …
    pub agent_type: String,
    pub is_enabled: bool,
}

impl CustomAgentCommand {
    /// An enabled command.
    pub fn new(command: &str, agent_type: &str) -> Self {
        Self {
            command: command.to_owned(),
            agent_type: agent_type.to_owned(),
            is_enabled: true,
        }
    }
}

/// `CustomAgentCommandStore.defaultSeededCommands`' candidates: what the
/// store holds when nothing was saved (as for the bridge, which has no app
/// preferences), each one only if its config directory exists.
const SEEDED_CANDIDATES: &[(&str, &str)] = &[
    ("claude-govtech", "/.claude-govtech"),
    ("claude-mantiq", "/.claude-mantiq"),
    ("claude-work", "/.claude-work"),
    ("claude-corp", "/.claude-corp"),
];

/// `CustomAgentCommandStore.defaultSeededCommands()`: the candidates whose
/// directory under `home` exists.
pub fn default_seeded_commands(
    home: &str,
    file_exists: impl Fn(&str) -> bool,
) -> Vec<CustomAgentCommand> {
    SEEDED_CANDIDATES
        .iter()
        .filter(|(_, dir)| file_exists(&format!("{home}{dir}")))
        .map(|(command, _)| CustomAgentCommand::new(command, "claude"))
        .collect()
}

impl SourceCatalog {
    /// `CustomAgentCommandStore.canonicalAgent(forCommand:)`.
    pub fn canonical_agent(&self, command: &str) -> Option<String> {
        let lower = command.to_lowercase();
        self.custom_commands
            .iter()
            .find(|c| c.command.to_lowercase() == lower && c.is_enabled)
            .map(|c| c.agent_type.to_lowercase())
    }

    /// `CustomAgentCommandStore.activeCommandNames(forAgent:)`.
    fn active_command_names(&self, agent: &str) -> Vec<String> {
        let agent = agent.to_lowercase();
        self.custom_commands
            .iter()
            .filter(|c| c.is_enabled && c.agent_type.to_lowercase() == agent)
            .map(|c| c.command.to_lowercase())
            .collect()
    }

    /// `CustomAgentCommandStore.matchesCustomCommand(path:agentType:)`.
    pub fn matches_custom_command(&self, path: &str, agent_type: &str) -> bool {
        let lower = path.to_lowercase();
        self.active_command_names(agent_type).iter().any(|name| {
            lower.ends_with(&format!("/{name}")) || lower.contains(&format!("/{name} "))
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seeded_commands_are_the_existing_directories() {
        let seeded = default_seeded_commands("/home/dev", |p| p == "/home/dev/.claude-work");
        assert_eq!(
            seeded,
            vec![CustomAgentCommand::new("claude-work", "claude")]
        );
    }

    #[test]
    fn a_custom_command_matches_its_agent_only() {
        let mut disabled = CustomAgentCommand::new("claude-off", "claude");
        disabled.is_enabled = false;
        let catalog = SourceCatalog {
            custom_sources: Vec::new(),
            custom_commands: vec![CustomAgentCommand::new("Claude-Work", "Claude"), disabled],
        };
        assert!(catalog.matches_custom_command("/usr/bin/claude-work", "claude"));
        assert!(!catalog.matches_custom_command("/usr/bin/claude-work", "codex"));
        assert!(!catalog.matches_custom_command("/usr/bin/claude-off", "claude"));
        assert_eq!(catalog.canonical_agent("claude-off"), None);
    }
}
