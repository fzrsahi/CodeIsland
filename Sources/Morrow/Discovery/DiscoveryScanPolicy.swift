import Foundation

/// Which file events are worth a discovery scan, and how often one may run.
///
/// The watcher used to rescan on every batch FSEvents delivered, and a scan
/// walks the whole process table. An agent writing its transcript therefore
/// bought a full scan roughly every two seconds — for a file discovery is
/// already following line by line. The writes that matter are the ones to the
/// stores nobody is tailing: a new session appearing, a lease, a WAL/SHM side
/// file. Those are counted; the transcript being tailed is not.
enum DiscoveryScanPolicy {
    /// Two scans closer together than this are one scan: the second waits.
    static let minimumGap: TimeInterval = 5

    /// Whether a changed path is news to discovery. A path the tailer is
    /// already following is not: the tailer sees every line as it lands.
    static func isInteresting(path: String, tailedPaths: Set<String>) -> Bool {
        !tailedPaths.contains(path)
    }

    /// Whether any path in a batch is news.
    static func hasInterestingEvent(paths: [String], tailedPaths: Set<String>) -> Bool {
        paths.contains { isInteresting(path: $0, tailedPaths: tailedPaths) }
    }
}

/// Leading + trailing throttle: a burst scans at once, then once more when the
/// quietest gap has passed. The trailing scan is never lost, so the last
/// lifecycle write of a burst is always read.
struct DiscoveryScanThrottle: Equatable {
    private(set) var lastScanAt: Date?
    var minimumGap: TimeInterval = DiscoveryScanPolicy.minimumGap

    enum Decision: Equatable {
        /// Scan now.
        case scanNow
        /// Scan when the gap has passed; arm a timer for this instant.
        case scanLater(Date)
        /// Nothing worth scanning.
        case ignore
    }

    /// What to do about a batch of events seen at `now`.
    mutating func decide(hasInterestingEvent: Bool, now: Date) -> Decision {
        guard hasInterestingEvent else { return .ignore }
        guard let lastScanAt else { return .scanNow }
        let elapsed = now.timeIntervalSince(lastScanAt)
        if elapsed >= minimumGap { return .scanNow }
        return .scanLater(lastScanAt.addingTimeInterval(minimumGap))
    }

    /// Record that a scan started; the next gap is measured from here.
    mutating func noteScanStarted(at now: Date) {
        lastScanAt = now
    }

    /// Forget the clock (watcher restart, stop).
    mutating func reset() {
        lastScanAt = nil
    }
}
