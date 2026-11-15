import Foundation
import CodeIslandCore

/// Send-or-skip decision for device publishers (Buddy ESP32 + iPhone
/// Companion): device payloads are published only when they change.
///
/// Pure function so it can be unit-tested without BLE/MCSession.
enum PublishDecision: Equatable, Sendable {
    case send
    case skip
}

enum PublishDedupe {
    /// Full-resync cadence for the ESP32 aux packets. The firmware drops out
    /// of AGENT mode after 60 s without writes; 30 s stays well inside that
    /// while keeping idle traffic low.
    static let fullResyncInterval: TimeInterval = 30

    /// Pure send-or-skip decision.
    ///
    /// - `lastSent`/`next`: stable content keys (e.g. base64 of the frame
    ///   bytes, or `companionContentKey`). A `nil` `next` means nothing to
    ///   send; a `nil` `lastSent` means no cache (first send, or right after
    ///   a reconnect cleared it) and always sends.
    /// - `isPrimaryFrame`: ESP32 main mascot frame. Always sent, even when
    ///   identical: the firmware uses inter-frame spacing for animation tempo.
    /// - `isHeartbeat`: periodic keepalive. Always sent (ESP32 tempo/60 s
    ///   timeout, iPhone 8–24 s watchdog).
    /// - `isInteractive`: interactive retry. Always a full resend so an
    ///   approval/question prompt never sticks on a stale Buddy screen.
    /// - `secondsSinceFullSync`: `.infinity` when no full sync happened yet
    ///   forces a send.
    static func shouldSend(
        lastSent: String?,
        next: String?,
        isPrimaryFrame: Bool,
        isHeartbeat: Bool,
        isInteractive: Bool,
        secondsSinceFullSync: TimeInterval
    ) -> PublishDecision {
        if isInteractive { return .send }
        if secondsSinceFullSync >= fullResyncInterval { return .send }
        guard let next else { return .skip }
        guard let lastSent else { return .send }
        if next != lastSent { return .send }
        if isHeartbeat { return .send }
        if isPrimaryFrame { return .send }
        return .skip
    }

    /// Stable content key for an Apple Companion payload, excluding `sequence`
    /// (a monotonic counter that changes on every flush) and the top-level
    /// `updatedAt` (wall-clock stamped at build time — keeping it would make
    /// every key unique and dedupe dead code). Per-session `updatedAt`s inside
    /// `sessions` are real activity timestamps and stay in the key.
    ///
    /// Field-agnostic (JSON round-trip with keys stripped) so future payload
    /// fields are compared automatically. Fail-open: an encoding failure
    /// returns a unique key so the payload sends rather than drops.
    static func companionContentKey(for payload: AppleCompanionStatePayload) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return UUID().uuidString
        }
        dict.removeValue(forKey: "sequence")
        dict.removeValue(forKey: "updatedAt")
        guard let normalized = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) else {
            return UUID().uuidString
        }
        return String(data: normalized, encoding: .utf8) ?? UUID().uuidString
    }
}
