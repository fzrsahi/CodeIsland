import AppKit
import ApplicationServices
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
            guard !RuntimeEnvironment.isRunningTests else { return }
            if isEnabled {
                ensureMailRunningInBackground()
                startPolling()
                startDockBadgeObserver()
                registerWorkspaceObservers()
                refresh(checkRemote: true)
            } else {
                stopPolling()
                stopDockBadgeObserver()
                unregisterWorkspaceObservers()
                unreadCount = 0
                recentMails = []
                knownLatestMailId = nil
                hasCompletedInitialBaseline = false
                lastProbedUnreadCount = nil
                lastProbedTopMessageId = nil
            }
        }
    }

    @Published public var unreadCount: Int = 0
    @Published public var recentMails: [MailItem] = []
    @Published public var isRefreshing: Bool = false
    @Published public var lastRefreshed: Date? = nil
    @Published public var showNewMailPeek: Bool = false
    @Published public var showMiniPeekBanner: Bool = false
    @Published public var latestMailForPeek: MailItem? = nil
    @Published public var showMailArrivalAnimation: Bool = false
    @Published public var latestArrivalMail: MailItem? = nil
    @Published public var arrivalAnimId: Int = 0
    @Published public var arrivalAnimStartTime: Date = Date()

    private var pollingTimer: Timer?
    private var dockObserver: AXObserver?
    private var dockObservedElement: AXUIElement?
    private var dockDebounceWorkItem: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var mailArrivalDismissTimer: Timer?
    private var knownLatestMailId: Int? = nil
    private var hasCompletedInitialBaseline: Bool = false
    private var lastProbedUnreadCount: Int? = nil
    private var lastProbedTopMessageId: Int? = nil
    private var lastRemoteCheckTime: Date = .distantPast
    private var isProbing: Bool = false
    private var pendingImmediateRefresh: Bool = false

    private init() {
        guard !RuntimeEnvironment.isRunningTests else { return }
        if isEnabled {
            ensureMailRunningInBackground()
            startPolling()
            startDockBadgeObserver()
            registerWorkspaceObservers()
            // Initial delayed fetch to avoid startup race
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.refresh(checkRemote: true)
            }
        }
    }

    deinit {
        dockDebounceWorkItem?.cancel()
        pollingTimer?.invalidate()
        mailArrivalDismissTimer?.invalidate()
        if let observer = dockObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
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
        guard isEnabled, !RuntimeEnvironment.isRunningTests else { return }
        // Fast 3s lightweight probe catches Mail push updates promptly while Dock AXObserver triggers instantaneously (<0.2s)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fastProbeOrSync()
            }
        }
    }

    public func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    // MARK: - Instant Dock Badge Watcher & Lightweight Fast Probe

    private func startDockBadgeObserver() {
        stopDockBadgeObserver()
        guard isEnabled, !RuntimeEnvironment.isRunningTests, AXIsProcessTrusted() else { return }
        guard let dockPid = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier else { return }

        var observer: AXObserver?
        guard AXObserverCreate(dockPid, Self.dockAXCallback, &observer) == .success, let observer else {
            return
        }

        let dockElement = AXUIElementCreateApplication(dockPid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, dockElement, kAXValueChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, dockElement, kAXTitleChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        self.dockObserver = observer
        self.dockObservedElement = dockElement
    }

    private func stopDockBadgeObserver() {
        dockDebounceWorkItem?.cancel()
        dockDebounceWorkItem = nil
        if let observer = dockObserver, let dockElement = dockObservedElement {
            AXObserverRemoveNotification(observer, dockElement, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, dockElement, kAXTitleChangedNotification as CFString)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        dockObserver = nil
        dockObservedElement = nil
    }

    private func registerWorkspaceObservers() {
        unregisterWorkspaceObservers()
        let wsCenter = NSWorkspace.shared.notificationCenter
        let wakeToken = wsCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(checkRemote: true)
            }
        }
        let launchToken = wsCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.dock" || app?.bundleIdentifier == "com.apple.mail" else { return }
            Task { @MainActor in
                if app?.bundleIdentifier == "com.apple.dock" {
                    self?.startDockBadgeObserver()
                }
                self?.refresh(checkRemote: false)
            }
        }
        workspaceObservers = [wakeToken, launchToken]
    }

    private func unregisterWorkspaceObservers() {
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceObservers.removeAll()
    }

    private static let dockAXCallback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        var isMail = (titleRef as? String) == "Mail"
        if !isMail {
            var urlRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef)
            if let url = urlRef as? URL, url.lastPathComponent == "Mail.app" {
                isMail = true
            }
        }
        guard isMail else { return }

        let manager = Unmanaged<MailManager>.fromOpaque(refcon).takeUnretainedValue()
        Task { @MainActor in
            manager.handleInstantMailSignal()
        }
    }

    private func handleInstantMailSignal() {
        guard isEnabled else { return }
        dockDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refresh(checkRemote: false)
        }
        dockDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func fastProbeOrSync() {
        guard isEnabled, !isRefreshing, !isProbing else { return }
        let isMailRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
        guard isMailRunning else { return }

        // Periodically kick Mail's remote IMAP/POP check every 30s alongside push
        if Date().timeIntervalSince(lastRemoteCheckTime) >= 30.0 {
            refresh(checkRemote: true)
            return
        }

        isProbing = true
        Task.detached(priority: .utility) { [weak self] in
            let script = """
            tell application "Mail"
                set unreadTotal to 0
                try
                    set unreadTotal to unread count of inbox
                end try
                set topId to 0
                try
                    if (count of messages of inbox) > 0 then
                        set topId to id of message 1 of inbox
                    end if
                end try
                return (unreadTotal as string) & "<#>" & (topId as string)
            end tell
            """
            let raw = AppleScriptRunner.current.evaluate(script, 4.0)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProbing = false
                guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty else { return }
                let parts = trimmed.components(separatedBy: "<#>")
                guard parts.count >= 2,
                      let count = Int(parts[0]),
                      let topId = Int(parts[1]) else { return }

                let changed = !self.hasCompletedInitialBaseline
                    || self.lastProbedUnreadCount != count
                    || self.lastProbedTopMessageId != topId

                self.lastProbedUnreadCount = count
                self.lastProbedTopMessageId = topId

                if changed {
                    self.refresh(checkRemote: false)
                }
            }
        }
    }

    /// Asynchronously refreshes unread count & recent unread messages
    public func refresh(checkRemote: Bool = true) {
        guard isEnabled else { return }
        if isRefreshing {
            pendingImmediateRefresh = true
            return
        }
        isRefreshing = true
        if checkRemote {
            lastRemoteCheckTime = Date()
        }

        let checkCommand = checkRemote ? "try\n                    check for new mail\n                end try" : ""

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
                \(checkCommand)
                set unreadTotal to 0
                try
                    set unreadTotal to unread count of inbox
                end try
                set topMsgId to 0
                try
                    if (count of messages of inbox) > 0 then
                        set topMsgId to id of message 1 of inbox
                    end if
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
                return (unreadTotal as string) & "<#TOP#>" & (topMsgId as string) & "<#HEADER#>" & mailList
            end tell
            """

            let rawOutput = AppleScriptRunner.current.evaluate(script, 25.0)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isRefreshing = false
                self.lastRefreshed = Date()
                if let output = rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                    self.parseOutput(output)
                }
                if self.pendingImmediateRefresh {
                    self.pendingImmediateRefresh = false
                    self.refresh(checkRemote: false)
                }
            }
        }
    }

    /// Evaluates whether the latest unread item represents a brand-new email arrival after the initial baseline
    public static func evaluateArrival(
        topItem: MailItem?,
        hasCompletedBaseline: Bool,
        knownLatestId: Int?
    ) -> (shouldTrigger: Bool, nextKnownLatestId: Int?, nextHasBaseline: Bool) {
        if !hasCompletedBaseline {
            return (false, topItem?.id ?? knownLatestId, true)
        }
        guard let topItem else {
            return (false, knownLatestId, true)
        }
        if let prev = knownLatestId {
            return (topItem.id > prev, max(prev, topItem.id), true)
        }
        return (true, topItem.id, true)
    }

    private func parseOutput(_ output: String) {
        let parts = output.components(separatedBy: "<#HEADER#>")
        guard !parts.isEmpty else { return }

        // 1. Unread count & top inbox message ID
        let headerFields = parts[0].components(separatedBy: "<#TOP#>")
        if let count = Int(headerFields[0].trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.unreadCount = count
            self.lastProbedUnreadCount = count
        }
        if headerFields.count > 1,
           let topMsgId = Int(headerFields[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.lastProbedTopMessageId = topMsgId
        }

        // 2. Mail list
        var parsedItems: [MailItem] = []
        if parts.count > 1 {
            let lines = parts[1].components(separatedBy: "<#LINE#>").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
        }

        // Detect new mail arrival (handles starting from 0 unread cleanly)
        let arrivalDecision = Self.evaluateArrival(
            topItem: parsedItems.first,
            hasCompletedBaseline: self.hasCompletedInitialBaseline,
            knownLatestId: self.knownLatestMailId
        )
        self.hasCompletedInitialBaseline = arrivalDecision.nextHasBaseline
        self.knownLatestMailId = arrivalDecision.nextKnownLatestId
        if arrivalDecision.shouldTrigger, let topItem = parsedItems.first {
            self.triggerNewMailArrival(topItem)
        }

        self.recentMails = parsedItems
    }

    /// Triggers a brief 3.8-second roller coaster mail arrival animation in the notch right wing
    public func triggerNewMailArrival(_ item: MailItem) {
        let isAutoPeek = UserDefaults.standard.object(forKey: SettingsKey.mailAutoPeekNewEmail) as? Bool ?? SettingsDefaults.mailAutoPeekNewEmail
        guard isAutoPeek else { return }
        self.latestArrivalMail = item
        self.arrivalAnimStartTime = Date()
        self.arrivalAnimId += 1
        mailArrivalDismissTimer?.invalidate()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            self.showMailArrivalAnimation = true
        }
        mailArrivalDismissTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    self?.showMailArrivalAnimation = false
                }
            }
        }
    }

    /// Dismisses the incoming mail animation immediately
    public func dismissMailArrival() {
        mailArrivalDismissTimer?.invalidate()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            self.showMailArrivalAnimation = false
        }
    }

    /// Legacy mini-peek methods for backwards compatibility
    public func triggerNewMailPeek(_ item: MailItem) {
        triggerNewMailArrival(item)
    }

    public func dismissMiniPeekBanner() {
        dismissMailArrival()
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
