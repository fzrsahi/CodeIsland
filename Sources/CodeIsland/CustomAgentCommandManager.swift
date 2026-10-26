import Foundation
import SwiftUI
import CodeIslandCore

@MainActor
public final class CustomAgentCommandManager: ObservableObject {
    public static let shared = CustomAgentCommandManager()

    @Published public var commands: [CustomAgentCommand] = []

    private init() {
        self.commands = CustomAgentCommandStore.loadCommands()
        syncAll()
    }

    /// Synchronize all custom commands with system hooks and extra config roots
    public func syncAll() {
        CustomAgentCommandStore.saveCommands(commands)

        let fm = FileManager.default
        let primaryClaude = ConfigInstaller.primaryConfigRoot(for: .claude)

        for cmd in commands where cmd.isEnabled {
            let path = cmd.configDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }

            let expandedPath = path.hasPrefix("~/")
                ? NSHomeDirectory() + "/" + path.dropFirst(2)
                : (path.hasPrefix("/") ? path : NSHomeDirectory() + "/" + path)

            guard fm.fileExists(atPath: expandedPath) else { continue }

            if cmd.agentType.lowercased() == "claude" {
                // Check if already in ExtraConfigDirs
                let existing = ExtraConfigDirs.load()
                let alreadyIn = existing.contains {
                    $0.cli == .claude && ExtraConfigDirs.isSameDirectory($0.path, as: expandedPath)
                }

                if !alreadyIn && !ExtraConfigDirs.isSameDirectory(expandedPath, as: primaryClaude) {
                    _ = ConfigInstaller.addExtraConfigDir(cli: .claude, rawPath: path)
                } else if alreadyIn {
                    // Ensure hooks are installed in this extra config dir
                    _ = ConfigInstaller.repairExtraConfigDirs(fm: fm)
                }
            } else if cmd.agentType.lowercased() == "codex" {
                let existing = ExtraConfigDirs.load()
                let alreadyIn = existing.contains {
                    $0.cli == .codex && ExtraConfigDirs.isSameDirectory($0.path, as: expandedPath)
                }
                if !alreadyIn {
                    _ = ConfigInstaller.addExtraConfigDir(cli: .codex, rawPath: path)
                }
            }
        }

        ClaudeConfigPaths.invalidateCache()
    }

    /// Add a new custom command, register its profile, and install hooks
    @discardableResult
    public func addCommand(
        command: String,
        displayName: String,
        agentType: String = "claude",
        configDirectory: String = ""
    ) -> (ok: Bool, message: String) {
        let trimmedCmd = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedCmd.isEmpty else { return (false, "Command name cannot be empty") }
        guard trimmedCmd.range(of: #"^[a-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return (false, "Command name must use letters, numbers, hyphens, or underscores (e.g. claude-govtech)")
        }

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? trimmedCmd
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        var dir = configDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if dir.isEmpty && agentType.lowercased() == "claude" {
            // Auto-fallback: check if ~/.<command> exists
            let candidate = NSHomeDirectory() + "/." + trimmedCmd
            if FileManager.default.fileExists(atPath: candidate) {
                dir = "~/." + trimmedCmd
            }
        }

        let newCmd = CustomAgentCommand(
            command: trimmedCmd,
            displayName: name,
            agentType: agentType,
            configDirectory: dir,
            isEnabled: true
        )

        if let idx = commands.firstIndex(where: { $0.id == trimmedCmd }) {
            commands[idx] = newCmd
        } else {
            commands.append(newCmd)
        }

        CustomAgentCommandStore.saveCommands(commands)
        syncAll()
        return (true, "Custom command '\(trimmedCmd)' registered and hooks configured!")
    }

    public func removeCommand(id: String) {
        guard let idx = commands.firstIndex(where: { $0.id == id }) else { return }
        let removed = commands.remove(at: idx)
        CustomAgentCommandStore.saveCommands(commands)

        // Clean up from extra config dirs if it was added
        if !removed.configDirectory.isEmpty {
            let expanded = removed.configDirectory.hasPrefix("~/")
                ? NSHomeDirectory() + "/" + removed.configDirectory.dropFirst(2)
                : removed.configDirectory
            let existing = ExtraConfigDirs.load()
            if let match = existing.first(where: { ExtraConfigDirs.isSameDirectory($0.path, as: expanded) }) {
                _ = ConfigInstaller.removeExtraConfigDir(id: match.id)
            }
        }
        ClaudeConfigPaths.invalidateCache()
    }

    public func toggleCommand(id: String, enabled: Bool) {
        guard let idx = commands.firstIndex(where: { $0.id == id }) else { return }
        commands[idx].isEnabled = enabled
        CustomAgentCommandStore.saveCommands(commands)
        syncAll()
    }

    /// Check if hooks are installed in this command's settings.json
    public func isHooksActive(for cmd: CustomAgentCommand) -> Bool {
        guard cmd.isEnabled else { return false }
        let path = cmd.configDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return true }

        let expanded = path.hasPrefix("~/")
            ? NSHomeDirectory() + "/" + path.dropFirst(2)
            : path

        let settingsPath = expanded + "/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }
        return !hooks.isEmpty
    }

    /// Reinstall/repair hooks in this command's settings.json
    public func reinstallHooks(for cmd: CustomAgentCommand) -> Bool {
        let path = cmd.configDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        let outcome = ConfigInstaller.addExtraConfigDir(cli: .claude, rawPath: path)
        syncAll()
        switch outcome {
        case .success: return true
        case .failure: return false
        }
    }

    /// Scan user home for any existing ~/.claude-* or ~/.codex-* profiles not yet added
    public func discoverUnconfiguredProfiles() -> [CustomAgentCommand] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: home) else { return [] }

        let existingPaths = Set(commands.map { cmd -> String in
            let p = cmd.configDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.hasPrefix("~/") { return home + "/" + p.dropFirst(2) }
            return p
        })

        var candidates: [CustomAgentCommand] = []
        for item in contents where item.hasPrefix(".claude-") {
            let fullPath = home + "/" + item
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                guard !existingPaths.contains(fullPath) else { continue }
                let cmdName = String(item.dropFirst()) // e.g. "claude-govtech"
                let displayName = cmdName.split(separator: "-").map(\.capitalized).joined(separator: " ")
                candidates.append(CustomAgentCommand(
                    command: cmdName,
                    displayName: displayName,
                    agentType: "claude",
                    configDirectory: "~/" + item,
                    isEnabled: true
                ))
            }
        }
        return candidates
    }
}
