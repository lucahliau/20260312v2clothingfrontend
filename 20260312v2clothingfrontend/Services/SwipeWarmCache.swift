import Foundation

/// Persists the last complete liked/loved snapshot (the Wardrobe's data) for
/// instant cold-start UI (mirrors FeedWarmCache). Only ever written with a
/// full list — never with a partial page or a filtered subset.
enum SwipeWarmCache {
    /// v2: liked-only records. The v1 file held a mixed, image-filtered
    /// 100-row window and is removed on first load.
    private static let fileName = "liked_swipes_warm_cache.json"
    private static let legacyFileName = "swipe_history_warm_cache.json"

    private struct Snapshot: Codable {
        let records: [SwipeRecord]
        let savedAt: TimeInterval
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("SwipeWarmCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { directory.appendingPathComponent(fileName) }

    static func save(records: [SwipeRecord]) {
        let snapshot = Snapshot(records: records, savedAt: Date().timeIntervalSince1970)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best effort
        }
    }

    /// Returns cached state when the file exists and decodes.
    static func load() -> (records: [SwipeRecord], savedAt: Date)? {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(legacyFileName))
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        guard !snapshot.records.isEmpty else { return nil }
        return (snapshot.records, Date(timeIntervalSince1970: snapshot.savedAt))
    }
}
