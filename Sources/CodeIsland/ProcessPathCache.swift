import Foundation

/// Executable paths read from the process table, for one discovery scan and
/// across scans.
///
/// A scan asks the same question — "what is this pid running?" — once per
/// source: fourteen sources times every pid was fourteen `proc_pidpath`
/// syscalls per process per scan. Within a scan the answer is read once and
/// shared; across scans it is kept per `(pid, start time)` so a still-running
/// process costs nothing at all.
final class ProcessPathCache: @unchecked Sendable {
    private let lock = NSLock()
    /// Answers kept across scans, keyed by process identity.
    private var remembered: [Key: String] = [:]
    /// Answers read during the scan in flight.
    private var scan: [Key: String] = [:]
    private var scanning = false

    struct Key: Hashable {
        let pid: pid_t
        let start: Date?
    }

    func beginScan() {
        lock.lock()
        scan = [:]
        scanning = true
        lock.unlock()
    }

    func endScan() {
        lock.lock()
        // What the scan learned outlives it; the next scan of a quiet machine
        // then reads no process at all.
        remembered.merge(scan) { _, new in new }
        // Keep the cache from tracking a day of short-lived processes.
        if remembered.count > 4096 { remembered.removeAll(keepingCapacity: true) }
        scan = [:]
        scanning = false
        lock.unlock()
    }

    func path(for identity: ProcessIdentity) -> String? {
        let key = Key(pid: identity.pid, start: identity.startTime)
        lock.lock()
        defer { lock.unlock() }
        return remembered[key]
    }

    func scanPath(for identity: ProcessIdentity) -> String? {
        let key = Key(pid: identity.pid, start: identity.startTime)
        lock.lock()
        defer { lock.unlock() }
        guard scanning else { return nil }
        return scan[key]
    }

    func store(_ path: String, for identity: ProcessIdentity) {
        let key = Key(pid: identity.pid, start: identity.startTime)
        lock.lock()
        if scanning { scan[key] = path } else { remembered[key] = path }
        lock.unlock()
    }

    /// Test/diagnostic hook: forget everything.
    func reset() {
        lock.lock()
        remembered.removeAll()
        scan.removeAll()
        lock.unlock()
    }
}
