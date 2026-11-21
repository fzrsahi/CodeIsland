import Foundation

public struct CustomAgentCommand: Codable, Identifiable, Equatable, Sendable {
    public var id: String { command.lowercased() }
    public var command: String               // e.g. "claude-govtech"
    public var displayName: String           // e.g. "Claude GovTech"
    public var agentType: String             // "claude", "codex", "gemini", "cursor", etc.
    public var configDirectory: String       // e.g. "~/.claude-govtech"
    public var isEnabled: Bool

    public init(
        command: String,
        displayName: String,
        agentType: String = "claude",
        configDirectory: String = "",
        isEnabled: Bool = true
    ) {
        self.command = command
        self.displayName = displayName
        self.agentType = agentType
        self.configDirectory = configDirectory
        self.isEnabled = isEnabled
    }
}

public enum CustomAgentCommandStore {
    public static let preferenceKey = "custom_agent_commands_list"

    public static func loadCommands(defaults: UserDefaults = .standard) -> [CustomAgentCommand] {
        guard let data = defaults.data(forKey: preferenceKey),
              let list = try? JSONDecoder().decode([CustomAgentCommand].self, from: data) else {
            return defaultSeededCommands()
        }
        // If stored list is empty, also seed from default detected directories
        if list.isEmpty {
            let seeded = defaultSeededCommands()
            if !seeded.isEmpty {
                saveCommands(seeded, defaults: defaults)
                return seeded
            }
        }
        return list
    }

    public static func saveCommands(_ commands: [CustomAgentCommand], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(commands) {
            defaults.set(data, forKey: preferenceKey)
        }
    }

    /// Automatically discover existing directories like ~/.claude-govtech, ~/.claude-mantiq, etc.
    public static func defaultSeededCommands() -> [CustomAgentCommand] {
        var list: [CustomAgentCommand] = []
        let home = NSHomeDirectory()
        let fm = FileManager.default

        // Auto-detect common or existing custom claude dirs on user machine
        let candidates = [
            ("claude-govtech", "Claude GovTech", home + "/.claude-govtech"),
            ("claude-mantiq", "Claude Mantiq", home + "/.claude-mantiq"),
            ("claude-work", "Claude Work", home + "/.claude-work"),
            ("claude-corp", "Claude Corp", home + "/.claude-corp")
        ]

        for (cmd, display, path) in candidates {
            if fm.fileExists(atPath: path) {
                list.append(CustomAgentCommand(
                    command: cmd,
                    displayName: display,
                    agentType: "claude",
                    configDirectory: "~/" + (path as NSString).lastPathComponent,
                    isEnabled: true
                ))
            }
        }
        return list
    }

    public static func activeCommands(forAgent agent: String = "claude") -> [CustomAgentCommand] {
        loadCommands().filter { $0.isEnabled && $0.agentType.lowercased() == agent.lowercased() }
    }

    public static func activeCommandNames(forAgent agent: String = "claude") -> Set<String> {
        Set(activeCommands(forAgent: agent).map { $0.command.lowercased() })
    }

    public static func activeConfigDirs(forAgent agent: String = "claude") -> [String] {
        let home = NSHomeDirectory()
        return activeCommands(forAgent: agent).compactMap { cmd in
            let dir = cmd.configDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dir.isEmpty else { return nil }
            if dir.hasPrefix("~/") {
                return home + "/" + dir.dropFirst(2)
            }
            return dir
        }
    }

    public static func matchesCustomCommand(path: String, agentType: String) -> Bool {
        let lower = path.lowercased()
        let names = activeCommandNames(forAgent: agentType)
        for name in names {
            if lower.hasSuffix("/\(name)") || lower.contains("/\(name) ") {
                return true
            }
        }
        return false
    }

    public static func canonicalAgent(forCommand command: String) -> String? {
        let lower = command.lowercased()
        let commands = loadCommands()
        return commands.first(where: { $0.command.lowercased() == lower && $0.isEnabled })?.agentType.lowercased()
    }
}
