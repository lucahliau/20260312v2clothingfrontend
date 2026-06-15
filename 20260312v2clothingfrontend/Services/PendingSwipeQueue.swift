import Foundation

/// Disk-backed queue of swipes recorded while offline (subway mode). The
/// backend's POST /swipes is an upsert, so replaying queued swipes is
/// idempotent — one entry per item, last action wins. Flushed when
/// connectivity returns (`ConnectivityMonitor`) and on app launch.
actor PendingSwipeQueue {
    static let shared = PendingSwipeQueue()

    private struct Entry: Codable, Hashable {
        let itemId: String
        let action: SwipeType
        let queuedAt: Date
    }

    private var entries: [Entry] = []
    private var loaded = false
    private var isFlushing = false
    /// Debounce/backoff timer for the next flush attempt.
    private var flushTask: Task<Void, Never>?
    /// Consecutive failed flush attempts — drives exponential backoff and, while
    /// > 0, hands the retry cadence to the backoff timer so continuous swiping
    /// can't hammer a struggling server.
    private var consecutiveFailures = 0

    /// Flush as soon as this many swipes are queued (snappy under fast swiping).
    private static let flushThreshold = 10
    /// Otherwise flush this long after the last swipe (coalesces a burst).
    private static let debounceNanos: UInt64 = 2_000_000_000
    /// One request carries at most this many swipes (backend caps the batch at 100).
    private static let batchSize = 100
    /// Cap the on-disk backlog — generous (swipes are valuable); drop oldest beyond it.
    private static let maxEntries = 2000
    private static let baseBackoffNanos: UInt64 = 1_000_000_000
    private static let maxBackoffNanos: UInt64 = 30_000_000_000

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PendingSwipes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("queue.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let stored = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = stored
    }

    private func persist() {
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: Self.fileURL)
        } else if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.fileURL)
        }
    }

    func enqueue(itemId: String, action: SwipeType) {
        loadIfNeeded()
        entries.removeAll { $0.itemId == itemId }
        entries.append(Entry(itemId: itemId, action: action, queuedAt: Date()))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        persist()
        // While backing off after a failure, let the backoff timer own the retry
        // cadence (a new swipe mustn't reset it and hammer a struggling server).
        guard consecutiveFailures == 0 else { return }
        scheduleFlush(afterNanos: entries.count >= Self.flushThreshold ? 0 : Self.debounceNanos)
    }

    func pendingCount() -> Int {
        loadIfNeeded()
        return entries.count
    }

    /// (Re)arm the flush timer. A new call supersedes the pending one, so a burst
    /// of swipes coalesces into a single delayed flush.
    private func scheduleFlush(afterNanos: UInt64) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            if afterNanos > 0 {
                try? await Task.sleep(nanoseconds: afterNanos)
                if Task.isCancelled { return }
            }
            await self?.flush()
        }
    }

    private static func backoffNanos(for failures: Int) -> UInt64 {
        let exponent = UInt64(min(max(failures - 1, 0), 5)) // 1, 2, 4, 8, 16, 32s
        return min(baseBackoffNanos << exponent, maxBackoffNanos)
    }

    /// A 4xx that retrying can't fix (malformed body, etc.) → drop the batch so
    /// it can't poison the queue. 429/408/425 stay retryable (the whole point of
    /// this fix), and 5xx / offline errors aren't `serverError` 4xx, so they
    /// retry too.
    private static func isPermanentRejection(_ error: Error) -> Bool {
        guard case NetworkError.serverError(let status, _, _) = error else { return false }
        if status == 429 || status == 408 || status == 425 { return false }
        return (400..<500).contains(status)
    }

    /// Flushes queued swipes in batches via `POST /swipes/batch`. On a retryable
    /// failure (rate limit, server trouble, offline) it keeps everything and
    /// re-arms with exponential backoff — a swipe is never lost and the user
    /// never sees an error. Idempotent on the server (upsert), so re-sending a
    /// chunk after a partial failure is safe.
    func flush() async {
        loadIfNeeded()
        guard !isFlushing, !entries.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !entries.isEmpty {
            let chunk = Array(entries.prefix(Self.batchSize))
            do {
                try await SwipeService.postSwipeBatch(
                    chunk.map { (itemId: $0.itemId, action: $0.action) }
                )
                // Remove exactly the entries we sent (matched by value). The actor
                // can process an enqueue during the await above, and its per-item
                // dedupe may reorder the front of the queue — so removeFirst(count)
                // could drop a fresher re-swipe. Set membership is reorder-safe.
                let sent = Set(chunk)
                entries.removeAll { sent.contains($0) }
                persist()
                consecutiveFailures = 0
            } catch {
                if Self.isPermanentRejection(error) {
                    let sent = Set(chunk)
                    entries.removeAll { sent.contains($0) }
                    persist()
                    consecutiveFailures = 0
                    continue
                }
                consecutiveFailures += 1
                scheduleFlush(afterNanos: Self.backoffNanos(for: consecutiveFailures))
                break
            }
        }
    }
}

extension Error {
    /// True when the failure means "no usable network right now" rather than
    /// a server-side rejection — the cases worth queueing/retrying for.
    /// `nonisolated` so it's callable from any actor (incl. catch guards).
    nonisolated var isOfflineConnectivityError: Bool {
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .dataNotAllowed, .internationalRoamingOff:
                return true
            default:
                return false
            }
        }
        if let networkError = self as? NetworkError, case .transient = networkError {
            return true
        }
        return false
    }
}
