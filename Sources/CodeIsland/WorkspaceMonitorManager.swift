import Foundation
import Combine
import SwiftUI
import AppKit

// MARK: - Git Models

public struct GitFileChange: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let filename: String
    public let status: String // "M", "A", "D", "??", "R"
    public let isStaged: Bool

    public var statusLabel: String {
        switch status {
        case "M": return "MODIFIED"
        case "A": return "ADDED"
        case "D": return "DELETED"
        case "??": return "UNTRACKED"
        case "R": return "RENAMED"
        default: return status
        }
    }

    public var statusColor: Color {
        switch status {
        case "M": return Color(red: 0.96, green: 0.62, blue: 0.04) // Neon Amber
        case "A", "??": return Color(red: 0.0, green: 0.90, blue: 0.46) // Emerald
        case "D": return Color(red: 1.0, green: 0.16, blue: 0.53) // Magenta/Red
        default: return Color(white: 0.6)
        }
    }
}

public struct GitCommitItem: Identifiable, Equatable, Sendable {
    public var id: String { hash }
    public let hash: String
    public let message: String
    public let author: String
    public let timeAgo: String
}

public enum TestRunnerStatus: Equatable {
    case idle
    case running
    case passed(Int)
    case failed(Int, String)
}

// MARK: - Workspace Monitor Manager

@MainActor
public final class WorkspaceMonitorManager: ObservableObject {
    public static let shared = WorkspaceMonitorManager()

    @Published public var currentCwd: String = ""
    @Published public var projectName: String = "Workspace"
    @Published public var branch: String = "main"
    @Published public var isGitRepo: Bool = false
    @Published public var aheadCount: Int = 0
    @Published public var behindCount: Int = 0
    @Published public var insertions: Int = 0
    @Published public var deletions: Int = 0
    @Published public var changedFiles: [GitFileChange] = []
    @Published public var recentCommits: [GitCommitItem] = []
    @Published public var selectedFilePath: String? = nil
    @Published public var selectedFileDiff: String = ""
    @Published public var isDiffLoading: Bool = false
    @Published public var isExpandedDetail: Bool = false
    @Published public var isRefreshing: Bool = false
    @Published public var detectedTestFramework: String? = nil
    @Published public var testStatus: TestRunnerStatus = .idle
    @Published public var testOutput: String = ""

    @Published public var isUserPinned: Bool = UserDefaults.standard.bool(forKey: "workspaceIsUserPinned")
    private var lastRefreshTime: Date = .distantPast
    private var refreshTask: Task<Void, Never>? = nil

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "lastWorkspaceCwd"),
           !saved.isEmpty, FileManager.default.fileExists(atPath: saved) {
            self.currentCwd = saved
            self.projectName = (saved as NSString).lastPathComponent
            detectTestFramework(cwd: saved)
            refresh(force: true)
        }
    }

    public func updateCwdIfNeeded(_ cwd: String?, forceUserPinned: Bool = false) {
        guard let cwd = cwd, !cwd.isEmpty else { return }
        // If user manually chose/pinned a workspace, do not overwrite with background agent hooks
        if isUserPinned && !forceUserPinned && cwd != currentCwd {
            return
        }
        if forceUserPinned {
            isUserPinned = true
            UserDefaults.standard.set(true, forKey: "workspaceIsUserPinned")
        }
        if cwd != currentCwd || !isGitRepo {
            currentCwd = cwd
            projectName = (cwd as NSString).lastPathComponent
            UserDefaults.standard.set(cwd, forKey: "lastWorkspaceCwd")
            detectTestFramework(cwd: cwd)
            refresh(force: true)
        }
    }

    func resolveAndRefreshWorkspace(appState: AppState) {
        // If user pinned a workspace, always respect it
        if isUserPinned && !currentCwd.isEmpty && FileManager.default.fileExists(atPath: currentCwd) {
            refresh(force: true)
            return
        }

        // 1. Check frontmost terminal window via TTY / CWD
        if let detected = detectFrontmostTerminalCwd(), !detected.isEmpty,
           FileManager.default.fileExists(atPath: detected) {
            updateCwdIfNeeded(detected)
            return
        }

        // 2. Active agent session cwd (filter out internal plugin configs like ~/.gemini/config)
        let isConfigDir = { (path: String) -> Bool in
            path.hasSuffix("/.gemini/config") || path.hasSuffix("/.config") || path.contains("/.gemini/")
        }

        if let sid = appState.activeSessionId, let cwd = appState.sessions[sid]?.cwd,
           !cwd.isEmpty, !isConfigDir(cwd) {
            updateCwdIfNeeded(cwd)
            return
        }

        for session in appState.sessions.values {
            if let cwd = session.cwd, !cwd.isEmpty, !isConfigDir(cwd) {
                updateCwdIfNeeded(cwd)
                return
            }
        }

        // 3. Saved workspace in UserDefaults
        if let saved = UserDefaults.standard.string(forKey: "lastWorkspaceCwd"),
           !saved.isEmpty, !isConfigDir(saved), FileManager.default.fileExists(atPath: saved) {
            updateCwdIfNeeded(saved)
            return
        }

        // 4. Any session cwd even if config
        if let sid = appState.activeSessionId, let cwd = appState.sessions[sid]?.cwd, !cwd.isEmpty {
            updateCwdIfNeeded(cwd)
            return
        }

        if !currentCwd.isEmpty {
            refresh(force: true)
        }
    }

    private func detectFrontmostTerminalCwd() -> String? {
        // Method A: Check active tab tty in Terminal.app, then resolve shell process cwd
        let termTtyScript = """
        tell application "System Events"
            if exists (process "Terminal") then
                tell application "Terminal"
                    try
                        return tty of selected tab of front window
                    end try
                end tell
            end if
        end tell
        return ""
        """
        if let ttyFull = AppleScriptRunner.osascript.evaluate(termTtyScript, 1.5)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !ttyFull.isEmpty {
            let ttyName = ttyFull.replacingOccurrences(of: "/dev/", with: "").replacingOccurrences(of: "tty", with: "")
            let psData = ProcessRunner.run(path: "/bin/ps", args: ["-t", ttyName, "-o", "pid="], timeout: 1.5)
            if let psText = psData.flatMap({ String(data: $0, encoding: .utf8) }) {
                let pids = psText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                for pidStr in pids.reversed() {
                    if let lsofData = ProcessRunner.run(path: "/usr/sbin/lsof", args: ["-a", "-p", pidStr, "-d", "cwd", "-Fn"], timeout: 1.5),
                       let lsofText = String(data: lsofData, encoding: .utf8) {
                        for line in lsofText.components(separatedBy: "\n") {
                            if line.hasPrefix("n/") {
                                let candidate = String(line.dropFirst(1)).trimmingCharacters(in: .whitespacesAndNewlines)
                                if FileManager.default.fileExists(atPath: candidate) && candidate != "/" {
                                    return candidate
                                }
                            }
                        }
                    }
                }
            }
        }

        // Method B: iTerm2
        let itermScript = """
        tell application "System Events"
            if exists (process "iTerm2") or exists (process "iTerm") then
                tell application "iTerm"
                    try
                        return variable named "user.currentDir" of current session of current window
                    end try
                end tell
            end if
        end tell
        return ""
        """
        if let itermDir = AppleScriptRunner.osascript.evaluate(itermScript, 1.5)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !itermDir.isEmpty,
           FileManager.default.fileExists(atPath: itermDir) {
            return itermDir
        }

        return nil
    }

    public func chooseWorkspaceFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.level = .floating
        panel.title = "Select Git Workspace / Project Folder"
        panel.prompt = "Choose Workspace"

        if panel.runModal() == .OK, let url = panel.url {
            updateCwdIfNeeded(url.path, forceUserPinned: true)
        }
    }

    public func resetToAutoDetect() {
        isUserPinned = false
        UserDefaults.standard.set(false, forKey: "workspaceIsUserPinned")
        if let detected = detectFrontmostTerminalCwd() {
            updateCwdIfNeeded(detected)
        } else {
            refresh(force: true)
        }
    }

    public func refresh(force: Bool = false) {
        guard !currentCwd.isEmpty else { return }
        let now = Date()
        if !force && now.timeIntervalSince(lastRefreshTime) < 2.0 {
            return
        }
        lastRefreshTime = now

        refreshTask?.cancel()
        refreshTask = Task.detached(priority: .userInitiated) { [cwd = currentCwd] in
            await MainActor.run { self.isRefreshing = true }

            let gitBinary = "/usr/bin/git"
            let fm = FileManager.default

            // 1. Check if git repo exists
            var isDir: ObjCBool = false
            let hasGit = fm.fileExists(atPath: cwd + "/.git", isDirectory: &isDir)

            if !hasGit {
                // Check git rev-parse inside
                let revData = ProcessRunner.run(path: gitBinary, args: ["-C", cwd, "rev-parse", "--is-inside-work-tree"], timeout: 3)
                let inside = revData.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
                guard inside else {
                    await MainActor.run {
                        self.isGitRepo = false
                        self.isRefreshing = false
                    }
                    return
                }
            }

            // 2. Fetch branch & remote tracking (ahead/behind)
            var branchName = "main"
            var ahead = 0
            var behind = 0
            var files: [GitFileChange] = []

            if let statusData = ProcessRunner.run(path: gitBinary, args: ["-C", cwd, "status", "--porcelain=v1", "-b"], timeout: 4),
               let statusText = String(data: statusData, encoding: .utf8) {
                let lines = statusText.components(separatedBy: "\n")
                for line in lines {
                    if line.hasPrefix("##") {
                        // e.g. ## main...origin/main [ahead 1, behind 2]
                        let branchInfo = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                        if let dotsIdx = branchInfo.range(of: "...") {
                            branchName = String(branchInfo[..<dotsIdx.lowerBound])
                        } else if let spaceIdx = branchInfo.range(of: " ") {
                            branchName = String(branchInfo[..<spaceIdx.lowerBound])
                        } else {
                            branchName = branchInfo
                        }
                        if let aheadIdx = branchInfo.range(of: "ahead ") {
                            let sub = branchInfo[aheadIdx.upperBound...]
                            ahead = Int(sub.prefix(while: { $0.isNumber })) ?? 0
                        }
                        if let behindIdx = branchInfo.range(of: "behind ") {
                            let sub = branchInfo[behindIdx.upperBound...]
                            behind = Int(sub.prefix(while: { $0.isNumber })) ?? 0
                        }
                    } else if line.count >= 3 {
                        let code = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                        let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                        if !path.isEmpty {
                            let filename = (path as NSString).lastPathComponent
                            files.append(GitFileChange(
                                path: path,
                                filename: filename,
                                status: code.isEmpty ? "M" : code,
                                isStaged: line.hasPrefix("M ") || line.hasPrefix("A ")
                            ))
                        }
                    }
                }
            }

            // 3. Fetch diff shortstat (insertions & deletions)
            var ins = 0
            var del = 0
            if let diffData = ProcessRunner.run(path: gitBinary, args: ["-C", cwd, "diff", "--shortstat"], timeout: 4),
               let diffText = String(data: diffData, encoding: .utf8) {
                // " 3 files changed, 45 insertions(+), 12 deletions(-)"
                if let insIdx = diffText.range(of: "insertion") {
                    let sub = diffText[..<insIdx.lowerBound].trimmingCharacters(in: .whitespaces)
                    let numStr = sub.components(separatedBy: ",").last?.components(separatedBy: " ").filter({ !$0.isEmpty }).last ?? ""
                    ins = Int(numStr) ?? 0
                }
                if let delIdx = diffText.range(of: "deletion") {
                    let sub = diffText[..<delIdx.lowerBound].trimmingCharacters(in: .whitespaces)
                    let numStr = sub.components(separatedBy: ",").last?.components(separatedBy: " ").filter({ !$0.isEmpty }).last ?? ""
                    del = Int(numStr) ?? 0
                }
            }

            // 4. Fetch recent commits (last 5)
            var commits: [GitCommitItem] = []
            if let logData = ProcessRunner.run(path: gitBinary, args: ["-C", cwd, "log", "-n", "5", "--pretty=format:%h|||%s|||%an|||%ar"], timeout: 4),
               let logText = String(data: logData, encoding: .utf8) {
                let lines = logText.components(separatedBy: "\n")
                for line in lines where !line.isEmpty {
                    let parts = line.components(separatedBy: "|||")
                    if parts.count >= 4 {
                        commits.append(GitCommitItem(
                            hash: parts[0],
                            message: parts[1],
                            author: parts[2],
                            timeAgo: parts[3]
                        ))
                    }
                }
            }

            let finalBranch = branchName
            let finalAhead = ahead
            let finalBehind = behind
            let finalIns = ins
            let finalDel = del
            let finalFiles = files
            let finalCommits = commits

            await MainActor.run {
                self.isGitRepo = true
                self.branch = finalBranch
                self.aheadCount = finalAhead
                self.behindCount = finalBehind
                self.insertions = finalIns
                self.deletions = finalDel
                self.changedFiles = finalFiles
                self.recentCommits = finalCommits
                self.isRefreshing = false

                // If a file was selected, refresh its diff
                if let sel = self.selectedFilePath {
                    self.fetchDiff(for: sel)
                } else if let first = finalFiles.first {
                    self.fetchDiff(for: first.path)
                }
            }
        }
    }

    public func fetchDiff(for filePath: String) {
        self.selectedFilePath = filePath
        self.isDiffLoading = true
        let cwd = self.currentCwd

        Task.detached(priority: .userInitiated) {
            let gitBinary = "/usr/bin/git"
            var diffOutput = ""

            if let data = ProcessRunner.run(path: gitBinary, args: ["-C", cwd, "diff", "--", filePath], timeout: 5),
               let txt = String(data: data, encoding: .utf8), !txt.isEmpty {
                diffOutput = txt
            } else if let data = ProcessRunner.run(path: gitBinary, args: ["-C", cwd, "diff", "--cached", "--", filePath], timeout: 5),
                      let txt = String(data: data, encoding: .utf8), !txt.isEmpty {
                diffOutput = txt
            } else {
                // Untracked or binary: show preview
                let fullPath = cwd + "/" + filePath
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                    diffOutput = content.components(separatedBy: "\n").prefix(50).joined(separator: "\n")
                } else {
                    diffOutput = "Binary file or no diff output available."
                }
            }

            let finalDiff = diffOutput
            await MainActor.run {
                self.selectedFileDiff = finalDiff
                self.isDiffLoading = false
            }
        }
    }

    private func detectTestFramework(cwd: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: cwd + "/Package.swift") {
            detectedTestFramework = "swift test"
        } else if fm.fileExists(atPath: cwd + "/package.json") {
            if fm.fileExists(atPath: cwd + "/bun.lockb") {
                detectedTestFramework = "bun test"
            } else if fm.fileExists(atPath: cwd + "/pnpm-lock.yaml") {
                detectedTestFramework = "pnpm test"
            } else {
                detectedTestFramework = "npm test"
            }
        } else if fm.fileExists(atPath: cwd + "/Cargo.toml") {
            detectedTestFramework = "cargo test"
        } else if fm.fileExists(atPath: cwd + "/go.mod") {
            detectedTestFramework = "go test ./..."
        } else if fm.fileExists(atPath: cwd + "/pytest.ini") || fm.fileExists(atPath: cwd + "/pyproject.toml") {
            detectedTestFramework = "pytest"
        } else {
            detectedTestFramework = nil
        }
    }

    public func runTests() {
        guard let runnerCmd = detectedTestFramework, !currentCwd.isEmpty else { return }
        self.testStatus = .running
        self.testOutput = "Executing \(runnerCmd)...\n"
        let cwd = self.currentCwd

        Task.detached(priority: .userInitiated) {
            let resultData = ProcessRunner.run(
                path: "/bin/sh",
                args: ["-c", "cd '\(cwd)' && \(runnerCmd)"],
                env: ["PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"],
                timeout: 30
            )

            let output = resultData.flatMap { String(data: $0, encoding: .utf8) } ?? "Test run completed with no output."
            let isPassed = !output.lowercased().contains("failed") && !output.lowercased().contains("error:")

            await MainActor.run {
                self.testOutput = output
                if isPassed {
                    self.testStatus = .passed(1)
                } else {
                    self.testStatus = .failed(1, "Tests failed")
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
            }
        }
    }

    // MARK: - Quick Actions

    public func openInEditor() {
        guard !currentCwd.isEmpty else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        let cwd = currentCwd

        // Try VS Code or Cursor
        DispatchQueue.global(qos: .userInitiated).async {
            if let _ = ProcessRunner.run(path: "/usr/local/bin/code", args: [cwd], timeout: 2) { return }
            if let _ = ProcessRunner.run(path: "/usr/local/bin/cursor", args: [cwd], timeout: 2) { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
        }
    }

    public func openInTerminal() {
        guard !currentCwd.isEmpty else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        let script = """
        tell application "Terminal"
            do script "cd \(currentCwd)"
            activate
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            AppleScriptRunner.osascript.launch(script)
        }
    }
}
