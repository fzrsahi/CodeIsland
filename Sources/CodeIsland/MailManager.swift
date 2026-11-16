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

    /// Parses an ISO8601 or Mail AppleScript timestamp into a `Date`.
    public static func parseISO8601Date(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.lowercased() == "recent" { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let parsed = formatter.date(from: trimmed) {
            return parsed
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let parsed = df.date(from: trimmed) {
            return parsed
        }

        let df2 = DateFormatter()
        df2.locale = Locale(identifier: "en_US_POSIX")
        df2.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df2.date(from: trimmed)
    }

    /// Returns `true` when the raw timestamp falls within the last `days` days (defaults to 7).
    public static func isDateWithinRecentWindow(_ raw: String, days: Int = 7, now: Date = Date()) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "recent" { return true }
        guard let date = parseISO8601Date(trimmed) else { return true }
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        return date >= cutoff
    }

    /// Formats an ISO8601 date string from Apple Mail into relative English time (e.g. "2m ago", "1h ago", "yesterday")
    public static func parseDateRelative(_ raw: String) -> String {
        guard let date = parseISO8601Date(raw) else {
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
                activateMonitoring(initialDelay: 0.0)
            } else {
                deactivateMonitoring()
            }
        }
    }

    /// Unread count within the recent 7-day window (drives tabbar badge and HUD header).
    @Published public var unreadCount: Int = 0
    /// Total unread count reported by Apple Mail's inbox across all dates (for context/change probing).
    @Published public var totalInboxUnreadCount: Int = 0
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
    private var dockMailItemElement: AXUIElement?
    private var dockDebounceWorkItem: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var mailArrivalDismissTimer: Timer?
    private var knownLatestMailId: Int? = nil
    @Published public private(set) var hasCompletedInitialBaseline: Bool = false
    private var baselineTotalInboxUnread: Int? = nil
    private var baselineSettledAt: Date = .distantFuture
    private var pendingCountTriggeredArrivals: Int = 0
    private var unreadObservationEpoch: Int = 0
    private var lastRemoteCheckTime: Date = .distantPast
    private var isProbing: Bool = false
    private var isCheckingRemote: Bool = false
    private var pendingImmediateRefresh: Bool = false

    private init() {
        guard !RuntimeEnvironment.isRunningTests else { return }
        if isEnabled {
            activateMonitoring(initialDelay: 0.5)
        }
    }

    private func activateMonitoring(initialDelay: TimeInterval) {
        resetSyncBaselineState()
        // Suppress arrival sounds/animations while Mail boots and finishes initial sync.
        baselineSettledAt = Date().addingTimeInterval(5.0)
        ensureMailRunningInBackground()
        startPolling()
        startDockBadgeObserver()
        registerWorkspaceObservers()
        if initialDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
                guard let self, self.isEnabled else { return }
                self.fastProbeOrSync()
                self.refresh(checkRemote: false)
            }
        } else {
            refresh(checkRemote: false)
        }
    }

    private func deactivateMonitoring() {
        stopPolling()
        stopDockBadgeObserver()
        unregisterWorkspaceObservers()
        resetSyncBaselineState()
        lastRemoteCheckTime = .distantPast
        dockMailItemElement = nil
    }

    private func resetSyncBaselineState() {
        unreadCount = 0
        totalInboxUnreadCount = 0
        recentMails = []
        knownLatestMailId = nil
        hasCompletedInitialBaseline = false
        baselineTotalInboxUnread = nil
        baselineSettledAt = .distantFuture
        pendingCountTriggeredArrivals = 0
        unreadObservationEpoch += 1
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
        // Poll every 5s without saturating Mail.app on large 14k+ inboxes; Dock AXObserver provides instant wakeups.
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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

    private func findMailDockItem(dockPid: pid_t) -> AXUIElement? {
        let dockApp = AXUIElementCreateApplication(dockPid)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockApp, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let lists = childrenRef as? [AXUIElement] else {
            return nil
        }
        for list in lists {
            var itemsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                  let items = itemsRef as? [AXUIElement] else {
                continue
            }
            for item in items {
                var urlRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &urlRef) == .success,
                   let url = urlRef as? URL, url.lastPathComponent == "Mail.app" {
                    return item
                }
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleRef) == .success,
                   (titleRef as? String) == "Mail" {
                    return item
                }
            }
        }
        return nil
    }

    private func readDockUnreadBadge() -> Int? {
        guard AXIsProcessTrusted() else { return nil }
        if dockMailItemElement == nil,
           let dockPid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier {
            dockMailItemElement = findMailDockItem(dockPid: dockPid)
        }
        guard let item = dockMailItemElement else { return nil }
        var statusRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &statusRef) == .success,
              let raw = statusRef as? String else {
            return nil
        }
        return Self.parseDockBadgeCount(raw)
    }

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
        let mailItem = findMailDockItem(dockPid: dockPid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, dockElement, kAXValueChangedNotification as CFString, refcon)
        AXObserverAddNotification(observer, dockElement, kAXTitleChangedNotification as CFString, refcon)
        if let mailItem {
            AXObserverAddNotification(observer, mailItem, kAXValueChangedNotification as CFString, refcon)
            AXObserverAddNotification(observer, mailItem, kAXTitleChangedNotification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        self.dockObserver = observer
        self.dockObservedElement = dockElement
        self.dockMailItemElement = mailItem
    }

    private func stopDockBadgeObserver() {
        dockDebounceWorkItem?.cancel()
        dockDebounceWorkItem = nil
        if let observer = dockObserver, let dockElement = dockObservedElement {
            AXObserverRemoveNotification(observer, dockElement, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(observer, dockElement, kAXTitleChangedNotification as CFString)
            if let mailItem = dockMailItemElement {
                AXObserverRemoveNotification(observer, mailItem, kAXValueChangedNotification as CFString)
                AXObserverRemoveNotification(observer, mailItem, kAXTitleChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        dockObserver = nil
        dockObservedElement = nil
        dockMailItemElement = nil
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
            // Only wake up the single-metric `unread count of inbox` probe; never mix
            // Dock AXStatusLabel into `baselineTotalInboxUnread` (Dock can include non-Inbox counts).
            self?.fastProbeOrSync()
        }
        dockDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func fastProbeOrSync() {
        guard isEnabled else { return }
        if dockObserver == nil && AXIsProcessTrusted() {
            startDockBadgeObserver()
        }

        let isMailRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
        guard isMailRunning else { return }

        // Kick Mail's remote IMAP/POP check every 45s asynchronously without blocking the fast unread probe
        if !isCheckingRemote && !isRefreshing && Date().timeIntervalSince(lastRemoteCheckTime) >= 45.0 {
            triggerRemoteMailCheck()
        }

        guard !isProbing, !isRefreshing, !isCheckingRemote else { return }
        isProbing = true
        Task.detached(priority: .utility) { [weak self] in
            // Single-property query (`unread count of inbox`) runs in ~0.14s even on 14k+ message inboxes
            // because it avoids resolving `count of messages` or `message 1` object indices.
            let script = """
            tell application "Mail"
                try
                    return unread count of inbox
                on error
                    return -1
                end try
            end tell
            """
            let raw = AppleScriptRunner.current.evaluate(script, 6.0)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isProbing = false
                guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let count = Int(trimmed), count >= 0 else { return }
                self.handleObservedUnreadCount(count, triggerDetailFetch: true)
            }
        }
    }

    private func triggerRemoteMailCheck() {
        isCheckingRemote = true
        lastRemoteCheckTime = Date()
        Task.detached(priority: .utility) { [weak self] in
            let script = """
            tell application "Mail"
                try
                    check for new mail
                end try
            end tell
            """
            _ = AppleScriptRunner.current.evaluate(script, 12.0)
            await MainActor.run { [weak self] in
                self?.isCheckingRemote = false
            }
        }
    }

    private func handleObservedUnreadCount(_ count: Int, triggerDetailFetch: Bool) {
        unreadObservationEpoch += 1
        let isSettled = hasCompletedInitialBaseline && Date() >= baselineSettledAt
        let jump = Self.evaluateUnreadCountJump(
            newCount: count,
            baselineUnreadCount: baselineTotalInboxUnread,
            isBaselineSettled: isSettled
        )
        let prev = baselineTotalInboxUnread
        baselineTotalInboxUnread = jump.nextBaseline
        totalInboxUnreadCount = count

        // Never play sounds, animate, or publish raw total inbox counts while initial baseline settles.
        guard isSettled else {
            if prev == nil && triggerDetailFetch && !isRefreshing {
                refresh(checkRemote: false)
            }
            return
        }

        if jump.shouldTrigger {
            pendingCountTriggeredArrivals += 1
            unreadCount += 1
            let placeholder = MailItem(
                id: knownLatestMailId ?? 0,
                senderRaw: "Apple Mail",
                senderName: "New Email",
                senderEmail: "",
                subject: "New message arrived",
                dateReceived: "just now",
                isRead: false
            )
            triggerNewMailArrival(latestArrivalMail ?? placeholder)
            if triggerDetailFetch {
                refresh(checkRemote: false, queueIfBusy: true)
            }
        } else if let prev, count < prev, triggerDetailFetch {
            refresh(checkRemote: false, queueIfBusy: true)
        }
    }

    /// Triggers a lightweight local refresh on tab open only when baseline is missing or data is stale (>15s).
    public func refreshIfNeededOnTabOpen() {
        guard isEnabled, !isRefreshing else { return }
        if !hasCompletedInitialBaseline {
            refresh(checkRemote: false)
            return
        }
        if let lastRefreshed, Date().timeIntervalSince(lastRefreshed) < 15.0 {
            return
        }
        refresh(checkRemote: false)
    }

    /// Asynchronously refreshes unread count & recent unread messages
    public func refresh(checkRemote: Bool = true, queueIfBusy: Bool = false) {
        guard isEnabled else { return }
        if isRefreshing {
            if queueIfBusy {
                pendingImmediateRefresh = true
            }
            return
        }
        isRefreshing = true
        let startEpoch = unreadObservationEpoch
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
                set recentUnreadCount to 0
                set mailList to ""
                if unreadTotal > 0 then
                    set msgs to {}
                    try
                        set msgs to messages 1 thru 35 of inbox
                    on error
                        try
                            set msgs to every message of inbox
                        end try
                    end try
                    if class of msgs is not list then set msgs to {msgs}
                    set cutoffDate to (current date) - (7 * days)
                    set parsedCount to 0
                    set olderStreak to 0
                    set isFirst to true
                    repeat with m in msgs
                        try
                            if isFirst then
                                set isFirst to false
                                try
                                    set topMsgId to id of m
                                end try
                            end if
                            set msgDateObj to date received of m
                            if msgDateObj < cutoffDate then
                                set olderStreak to olderStreak + 1
                                if olderStreak >= 3 then exit repeat
                            else
                                set olderStreak to 0
                                if not (read status of m) then
                                    set recentUnreadCount to recentUnreadCount + 1
                                    if parsedCount < 6 then
                                        set msgId to id of m
                                        set msgSender to sender of m as string
                                        set msgSubj to subject of m as string
                                        set msgDate to "Recent"
                                        try
                                            set msgDate to msgDateObj as «class isot» as string
                                        end try
                                        set mailList to mailList & (msgId as string) & "<|>" & msgSender & "<|>" & msgSubj & "<|>" & msgDate & "<#LINE#>"
                                        set parsedCount to parsedCount + 1
                                    end if
                                end if
                            end if
                        end try
                    end repeat
                end if
                return (unreadTotal as string) & "<#TOP#>" & (topMsgId as string) & "<#RECENT#>" & (recentUnreadCount as string) & "<#HEADER#>" & mailList
            end tell
            """

            let rawOutput = AppleScriptRunner.current.evaluate(script, 40.0)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isRefreshing = false
                self.lastRefreshed = Date()
                if let output = rawOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty {
                    self.parseOutput(output, startedAtEpoch: startEpoch)
                }
                if self.pendingImmediateRefresh {
                    self.pendingImmediateRefresh = false
                    self.refresh(checkRemote: false)
                }
            }
        }
    }

    /// Formats the tabbar unread badge string (`1...99` or `"99+"` when above 99).
    nonisolated public static func formatBadgeCount(_ count: Int) -> String {
        if count > 99 { return "99+" }
        return "\(max(0, count))"
    }

    /// Extracts an integer badge count from Dock's localized `AXStatusLabel` string (e.g. "14,472").
    nonisolated public static func parseDockBadgeCount(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    /// Evaluates whether an unread-count sample jumped upward after the initial baseline was established and settled.
    nonisolated public static func evaluateUnreadCountJump(
        newCount: Int,
        baselineUnreadCount: Int?,
        isBaselineSettled: Bool = true
    ) -> (shouldTrigger: Bool, nextBaseline: Int) {
        guard isBaselineSettled, let prev = baselineUnreadCount else {
            return (false, newCount)
        }
        return (newCount > prev, newCount)
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

    private func parseOutput(_ output: String, startedAtEpoch: Int) {
        let parts = output.components(separatedBy: "<#HEADER#>")
        guard !parts.isEmpty else { return }

        // 1. Total inbox unread count, top inbox message ID, and recent (7d) unread count
        let headerFields = parts[0].components(separatedBy: "<#TOP#>")
        if let totalCount = Int(headerFields[0].trimmingCharacters(in: .whitespacesAndNewlines)) {
            if startedAtEpoch == self.unreadObservationEpoch || self.baselineTotalInboxUnread == nil {
                self.totalInboxUnreadCount = totalCount
                self.baselineTotalInboxUnread = totalCount
            }
        }

        var parsedRecentCount: Int? = nil
        if headerFields.count > 1 {
            let subFields = headerFields[1].components(separatedBy: "<#RECENT#>")
            if subFields.count > 1,
               let recent = Int(subFields[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                parsedRecentCount = recent
            }
        }

        // 2. Mail list (filtered to recent 7-day window)
        var parsedItems: [MailItem] = []
        if parts.count > 1 {
            let lines = parts[1].components(separatedBy: "<#LINE#>").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            for line in lines {
                let fields = line.components(separatedBy: "<|>")
                guard fields.count >= 4, let id = Int(fields[0].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    continue
                }
                let rawDate = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
                guard MailItem.isDateWithinRecentWindow(rawDate, days: 7) else {
                    continue
                }
                let senderRaw = fields[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
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

        if let recentCount = parsedRecentCount {
            if startedAtEpoch == self.unreadObservationEpoch || !self.hasCompletedInitialBaseline {
                self.unreadCount = max(recentCount, parsedItems.count)
            }
        } else {
            self.unreadCount = parsedItems.count
        }

        // Detect new mail arrival strictly AFTER initial baseline has completed and settled.
        let hadCompletedBaseline = self.hasCompletedInitialBaseline
        let isSettledForArrival = hadCompletedBaseline && Date() >= self.baselineSettledAt
        let arrivalDecision = Self.evaluateArrival(
            topItem: parsedItems.first,
            hasCompletedBaseline: hadCompletedBaseline,
            knownLatestId: self.knownLatestMailId
        )
        self.hasCompletedInitialBaseline = arrivalDecision.nextHasBaseline
        self.knownLatestMailId = arrivalDecision.nextKnownLatestId
        if !hadCompletedBaseline {
            self.baselineSettledAt = max(self.baselineSettledAt, Date().addingTimeInterval(1.5))
            self.pendingCountTriggeredArrivals = 0
        } else if arrivalDecision.shouldTrigger, let topItem = parsedItems.first {
            if self.pendingCountTriggeredArrivals > 0 {
                self.pendingCountTriggeredArrivals = 0
                self.latestArrivalMail = topItem
            } else if isSettledForArrival {
                self.triggerNewMailArrival(topItem)
            }
        }

        self.recentMails = parsedItems
    }

    /// Triggers a brief 3.8-second roller coaster mail arrival animation in the notch right wing
    public func triggerNewMailArrival(_ item: MailItem) {
        SoundManager.shared.playMailArrivalSound()

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
            self.totalInboxUnreadCount = max(0, self.totalInboxUnreadCount - 1)
            self.baselineTotalInboxUnread = self.totalInboxUnreadCount
            self.unreadObservationEpoch += 1
        }

        Task.detached(priority: .userInitiated) {
            let script = """
            tell application "Mail"
                try
                    set (read status of (first message of inbox whose id is \(id))) to true
                end try
            end tell
            """
            _ = AppleScriptRunner.current.evaluate(script, 20.0)
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
            _ = AppleScriptRunner.current.evaluate(script, 20.0)
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
