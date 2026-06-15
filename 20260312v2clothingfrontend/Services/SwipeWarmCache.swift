import Foundation

/// Persists the last swipe history snapshot for instant cold-start UI (mirrors FeedWarmCache).
enum SwipeWarmCache {
    private static let fileName = "swipe_history_warm_cache.json"

    private struct Snapshot: Codable {
        let records: [SwipeRecord]
        let isPreviewOnly: Bool
        let savedAt: TimeInterval
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("SwipeWarmCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func save(records: [SwipeRecord], isPreviewOnly: Bool) {
        let snapshot = Snapshot(
            records: records,
            isPreviewOnly: isPreviewOnly,
            savedAt: Date().timeIntervalSince1970
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best effort
        }
    }

    /// Returns cached state when the file exists and decodes.
    static func load() -> (records: [SwipeRecord], isPreviewOnly: Bool, savedAt: Date)? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        guard !snapshot.records.isEmpty else { return nil }
        let savedAt = Date(timeIntervalSince1970: snapshot.savedAt)
        return (snapshot.records, snapshot.isPreviewOnly, savedAt)
    }
}
