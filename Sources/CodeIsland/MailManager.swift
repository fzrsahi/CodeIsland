import Foundation
import SwiftUI
import CodeIslandCore

/// Model representing a single unread email item
public struct MailItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public let senderRaw: String
    public let senderName: String
    public let senderEmail: String
    public let subject: String
    public let dateReceived: String
    public var isRead: Bool

    public var avatarInitials: String {
        let trimmed = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "✉️" }
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 {
            let first = words[0].prefix(1)
            let second = words[1].prefix(1)
            return "\(first)\(second)".uppercased()
        } else if let single = words.first, single.count >= 2 {
            return String(single.prefix(2)).uppercased()
        } else if let single = words.first {
            return String(single.prefix(1)).uppercased()
        }
        return "✉️"
    }

    /// Generates a consistent pastel gradient for the sender avatar
    public var avatarGradient: [Color] {
        let hash = abs(senderRaw.hashValue)
        let palettes: [[Color]] = [
            [Color(red: 0.25, green: 0.52, blue: 0.96), Color(red: 0.40, green: 0.70, blue: 1.0)], // Royal Blue
            [Color(red: 0.95, green: 0.40, blue: 0.35), Color(red: 1.0, green: 0.65, blue: 0.45)],  // Coral Sunset
            [Color(red: 0.55, green: 0.35, blue: 0.95), Color(red: 0.75, green: 0.55, blue: 1.0)],  // Purple
            [Color(red: 0.12, green: 0.75, blue: 0.48), Color(red: 0.30, green: 0.90, blue: 0.65)],  // Mint Green
            [Color(red: 0.95, green: 0.65, blue: 0.15), Color(red: 1.0, green: 0.82, blue: 0.35)],  // Amber Gold
            [Color(red: 0.90, green: 0.25, blue: 0.60), Color(red: 1.0, green: 0.50, blue: 0.80)]   // Rose Magenta
        ]
        return palettes[hash % palettes.count]
    }

    public static func parseSender(_ raw: String) -> (name: String, email: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Matches "Name <email@example.com>"
        if let openBracket = trimmed.range(of: "<"),
           let closeBracket = trimmed.range(of: ">", range: openBracket.upperBound..<trimmed.endIndex) {
            let name = String(trimmed[..<openBracket.lowerBound]).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"")))
            let email = String(trimmed[openBracket.upperBound..<closeBracket.lowerBound]).trimmingCharacters(in: .whitespaces)
            return (name.isEmpty ? email : name, email)
        }
        return (trimmed, trimmed)
    }

    /// Formats an ISO8601 date string from Apple Mail into relative English time (e.g. "2m ago", "1h ago", "yesterday")
    public static func parseDateRelative(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "recent" { return "just now" }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        var parsedDate = formatter.date(from: trimmed)

        if parsedDate == nil {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            parsedDate = df.date(from: trimmed)
        }

        if parsedDate == nil {
            let df2 = DateFormatter()
            df2.locale = Locale(identifier: "en_US_POSIX")
            df2.dateFormat = "yyyy-MM-dd HH:mm:ss"
            parsedDate = df2.date(from: trimmed)
        }

        guard let date = parsedDate else {
            return "just now"
        }

        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let mins = max(1, seconds / 60)
            return "\(mins)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            if days == 1 {
                return "yesterday"
            } else {
                return "\(days)d ago"
            }
        }
    }
}

/// Central manager for Apple Mail integration via asynchronous AppleScript execution
@MainActor
public final class MailManager: ObservableObject {
    public static let shared = MailManager()

    @AppStorage(SettingsKey.mailIntegrationEnabled) public var isEnabled: Bool = SettingsDefaults.mailIntegrationEnabled {
        didSet {
            if isEnabled {
                ensureMailRunningInBackground()
                startPolling()
                refresh()
            } else {
                stopPolling()
                unreadCount = 0
                recentMails = []
            }
        }
    }

    @Published public var unreadCount: Int = 0
    @Published public var recentMails: [MailItem] = []
    @Published public var isRefreshing: Bool = false
    @Published public var lastRefreshed: Date? = nil
    @Published public var showNewMailPeek: Bool = false
    @Published public var latestMailForPeek: MailItem? = nil

    private var pollingTimer: Timer?
    private var peekDismissTimer: Timer?
    private var knownLatestMailId: Int? = nil

    private init() {
        if isEnabled {
            ensureMailRunningInBackground()
            startPolling()
            // Initial delayed fetch to avoid startup race
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.refresh()
            }
        }
    }

    /// Ensures Apple Mail is running silently in the background without opening windows or stealing focus
    public func ensureMailRunningInBackground() {
        Task.detached(priority: .utility) {
            let script = """
            set wasRunning to (application "Mail" is running)
            if not wasRunning then
                try
                    do shell script "open -g -j -a Mail"
                    delay 0.5
                    tell application "Mail"
                        close every window
                    end tell
                    tell application "System Events"
                        if exists (process "Mail") then
                            set visible of process "Mail" to false
                        end if
                    end tell
                end try
            end if
            """
            _ = AppleScriptRunner.current.evaluate(script, 6.0)
        }
    }

    public func startPolling() {
        stopPolling()
        guard isEnabled else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 45.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    public func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// Asynchronously refreshes unread count & recent unread messages
    public func refresh() {
        guard isEnabled else { return }
        guard !isRefreshing else { return }
        isRefreshing = true

        Task.detached(priority: .userInitiated) { [weak self] in
            let script = """
            set wasRunning to (application "Mail" is running)
            if not wasRunning then
                try
                    do shell script "open -g -j -a Mail"
                    delay 0.5
                    tell application "Mail"
                        close every window
                    end tell
                    tell application "System Events"
                        if exists (process "Mail") then
                            set visible of process "Mail" to false
                        end if
                    end tell
                end try
            end if

            tell application "Mail"
                set unreadTotal to 0
                try
                    set unreadTotal to unread count of inbox
                end try
                set mailList to ""
                repeat with i from 1 to 5
                    try
                        set m to message i of inbox
                        if not (read status of m) then
                            set msgId to id of m as string
                            set msgSender to sender of m as string
                            set msgSubj to subject of m as string
                            set msgDate to "Recent"
                            try
                                set msgDate to (date received of m) as «class isot» as string
                            end try
                            set mailList to mailList & msgId & "<|>" & msgSender & "<|>" & msgSubj & "<|>" & msgDate & "<#LINE#>"
                        end if
                    end try
                end repeat
                return (unreadTotal as string) & "<#HEADER#>" & mailList
            end tell
            """

            let rawOutput = AppleScriptRunner.current.evaluate(script, 25.0)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isRefreshing = false
                self.lastRefreshed = Date()
                guard let output = rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
                    return
                }

                self.parseOutput(output)
            }
        }
    }

    private func parseOutput(_ output: String) {
        let parts = output.components(separatedBy: "<#HEADER#>")
        guard !parts.isEmpty else { return }

        // 1. Unread count
        if let count = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.unreadCount = count
        }

        guard parts.count > 1 else {
            self.recentMails = []
            return
        }

        // 2. Mail list
        let lines = parts[1].components(separatedBy: "<#LINE#>").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var parsedItems: [MailItem] = []

        for line in lines {
            let fields = line.components(separatedBy: "<|>")
            guard fields.count >= 4, let id = Int(fields[0].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                continue
            }
            let senderRaw = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let rawDate = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let dateReceived = MailItem.parseDateRelative(rawDate)
            let (name, email) = MailItem.parseSender(senderRaw)

            let item = MailItem(
                id: id,
                senderRaw: senderRaw,
                senderName: name,
                senderEmail: email,
                subject: subject.isEmpty ? "(No Subject)" : subject,
                dateReceived: dateReceived,
                isRead: false
            )
            parsedItems.append(item)
        }

        // Detect new mail arrival for auto-peek
        if let topItem = parsedItems.first {
            if let lastKnown = self.knownLatestMailId, topItem.id > lastKnown {
                self.triggerNewMailPeek(topItem)
            }
            self.knownLatestMailId = topItem.id
        }

        self.recentMails = parsedItems
    }

    /// Triggers a brief 5-second auto-peek notification for incoming mail
    public func triggerNewMailPeek(_ item: MailItem) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.mailAutoPeekNewEmail) else { return }
        self.latestMailForPeek = item
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.showNewMailPeek = true
        }
        peekDismissTimer?.invalidate()
        peekDismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    self?.showNewMailPeek = false
                }
            }
        }
    }

    /// Marks an email as read both optimistically in local state and in Apple Mail.app
    public func markAsRead(id: Int) {
        // Optimistic local update
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.recentMails.removeAll { $0.id == id }
            self.unreadCount = max(0, self.unreadCount - 1)
        }

        Task.detached(priority: .userInitiated) {
            let script = """
            tell application "Mail"
                try
                    set (read status of (first message of inbox whose id is \(id))) to true
                end try
            end tell
            """
            _ = AppleScriptRunner.current.evaluate(script, 5.0)
        }
    }

    /// Activates Apple Mail.app and opens the specified message
    public func openInMailApp(id: Int) {
        Task.detached(priority: .userInitiated) {
            let script = """
            tell application "Mail"
                activate
                try
                    open (first message of inbox whose id is \(id))
                end try
            end tell
            """
            _ = AppleScriptRunner.current.evaluate(script, 5.0)
        }
    }

    /// Activates Apple Mail.app to view inbox
    public func openMailInbox() {
        Task.detached(priority: .userInitiated) {
            let script = """
            tell application "Mail"
                activate
            end tell
            """
            _ = AppleScriptRunner.current.evaluate(script, 5.0)
        }
    }
}
