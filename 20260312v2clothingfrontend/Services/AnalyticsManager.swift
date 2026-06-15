import Foundation
import Observation

// MARK: - Wire types (match the backend POST /v1/analytics/ingest schema)

// `nonisolated`: the project defaults to MainActor isolation, but these DTOs
// are encoded from inside the `AnalyticsQueue` actor — an actor-isolated
// context can't use a MainActor-isolated Codable conformance (a hard error in
// Swift 6 language mode).
private nonisolated struct AnalyticsEventPayload: Codable, Sendable {
    let eventName: String
    let screenName: String?
    let metadata: [String: String]?
    /// ISO8601 string, not a Date: NetworkManager.requestVoid encodes the body
    /// with a default JSONEncoder (which would serialize Date as a 2001
    /// reference-time double the backend can't parse), so we format it here.
    let clientTs: String
}

private nonisolated struct AnalyticsBatch: Codable, Sendable {
    let sessionId: String
    let events: [AnalyticsEventPayload]
}

// MARK: - Disk-backed event queue (runs off the main actor)

/// Append-only queue of analytics events, persisted so events survive a cold
/// start. A near-clone of `PendingSwipeQueue`: enqueue is cheap and
/// non-blocking; flush batches events to the backend fire-and-forget and stops
/// at the first connectivity failure (retried on the next trigger). The ingest
/// endpoint is `optionalAuth`, so it never 401s — analytics never logs anyone
/// out and never triggers a token refresh.
actor AnalyticsQueue {
    static let shared = AnalyticsQueue()

    private struct Entry: Codable {
        let sessionId: String
        let eventName: String
        let screenName: String?
        let metadata: [String: String]?
        let clientTs: String
    }

    private var entries: [Entry] = []
    private var loaded = false
    private var isFlushing = false

    /// Bound memory/disk: analytics is best-effort, so once the backlog is huge
    /// (e.g. offline for a long time) drop the OLDEST events rather than grow
    /// unbounded.
    private static let maxEntries = 500
    /// One request carries at most this many events (backend caps the batch at 100).
    private static let batchSize = 100

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Analytics", isDirectory: true)
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

    func enqueue(
        sessionId: String,
        eventName: String,
        screenName: String?,
        metadata: [String: String]?,
        clientTs: String
    ) {
        loadIfNeeded()
        entries.append(
            Entry(
                sessionId: sessionId,
                eventName: eventName,
                screenName: screenName,
                metadata: metadata,
                clientTs: clientTs
            )
        )
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        persist()
    }

    func pendingCount() -> Int {
        loadIfNeeded()
        return entries.count
    }

    /// Sends queued events oldest-first, one request per session (the ingest
    /// payload carries a single `sessionId`). Events are appended in time order,
    /// so a session's events form a contiguous run at the front of the queue.
    /// Stops at the first failure; the next trigger retries.
    func flush() async {
        loadIfNeeded()
        guard !isFlushing, !entries.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        while !entries.isEmpty {
            let sessionId = entries[0].sessionId
            var chunk: [Entry] = []
            var idx = 0
            while idx < entries.count, chunk.count < Self.batchSize, entries[idx].sessionId == sessionId {
                chunk.append(entries[idx])
                idx += 1
            }

            let batch = AnalyticsBatch(
                sessionId: sessionId,
                events: chunk.map {
                    AnalyticsEventPayload(
                        eventName: $0.eventName,
                        screenName: $0.screenName,
                        metadata: $0.metadata,
                        clientTs: $0.clientTs
                    )
                }
            )

            do {
                try await NetworkManager.shared.requestVoid(
                    "/v1/analytics/ingest",
                    method: "POST",
                    body: batch,
                    authenticated: true
                )
                entries.removeFirst(chunk.count)
                persist()
            } catch {
                // Offline or server trouble — keep everything and retry on the
                // next trigger (foreground, connectivity restore, or threshold).
                break
            }
        }
    }
}

// MARK: - Main-actor coordinator (the public API used by views/view models)

/// Thin façade over `AnalyticsQueue`. Owns the per-foreground `sessionId` and
/// the flush policy. `track(...)` is non-blocking: it stamps the time on the
/// main actor and hops to the queue actor to enqueue, so call sites stay cheap.
@Observable
@MainActor
final class AnalyticsManager {
    static let shared = AnalyticsManager()

    @ObservationIgnored private var sessionId = UUID().uuidString
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var eventsSinceFlush = 0

    /// Flush after this many tracked events even without a foreground/connectivity
    /// trigger, so a long active session still ships data periodically.
    private static let flushEveryNEvents = 20

    private init() {}

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Drains any events left on disk from a previous run. Call once on launch.
    func startup() {
        flushNow()
    }

    /// New foreground session: rotate the session id and stamp the start.
    /// Guarded so a brief `.inactive` → `.active` flicker (control center, a
    /// permission prompt) doesn't spawn a second session.
    func startSession() {
        guard sessionStart == nil else { return }
        sessionId = UUID().uuidString
        sessionStart = Date()
        track("session_start")
    }

    /// App backgrounded: record session length and force a flush so the session
    /// is captured promptly. No-op if no session is active.
    func endSession() {
        guard let start = sessionStart else { return }
        track("session_end", metadata: ["durationMs": String(Int(Date().timeIntervalSince(start) * 1000))])
        sessionStart = nil
        flushNow()
    }

    /// Enqueue an event. Non-blocking; safe to call from any view/view-model on
    /// the main actor.
    func track(_ eventName: String, screen: String? = nil, metadata: [String: String]? = nil) {
        let sid = sessionId
        let ts = Self.iso.string(from: Date())
        Task.detached(priority: .utility) {
            await AnalyticsQueue.shared.enqueue(
                sessionId: sid,
                eventName: eventName,
                screenName: screen,
                metadata: metadata,
                clientTs: ts
            )
        }
        eventsSinceFlush += 1
        if eventsSinceFlush >= Self.flushEveryNEvents {
            flushNow()
        }
    }

    func flushNow() {
        eventsSinceFlush = 0
        Task.detached(priority: .utility) {
            await AnalyticsQueue.shared.flush()
        }
    }
}
