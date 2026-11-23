import Foundation

/// Persists the first few feed items + filter fingerprint for instant cold-start UI.
enum FeedWarmCache {
    // 15 cards (~2-4KB JSON each) covers a whole session of swipes before the
    // background network refresh has to land.
    private static let maxItems = 15
    private nonisolated static let fileName = "feed_warm_cache.json"

    private struct Snapshot: Codable {
        let items: [Item]
        let productTypes: [String]
        let genders: [String]
    }

    private nonisolated static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FeedWarmCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    /// Serial queue so snapshot writes land in the order they were requested.
    private nonisolated static let writeQueue = DispatchQueue(label: "feed-warm-cache-write", qos: .utility)

    private static func fingerprint(
        productTypes: Set<ProductType>,
        genders: Set<GenderFilter>
    ) -> (productTypes: [String], genders: [String]) {
        let pt = productTypes.isEmpty ? [] : productTypes.map(\.rawValue).sorted()
        let g = genders.isEmpty ? [] : genders.map(\.rawValue).sorted()
        return (pt, g)
    }

    private static func matches(
        _ snapshot: Snapshot,
        productTypes: Set<ProductType>,
        genders: Set<GenderFilter>
    ) -> Bool {
        let fp = fingerprint(productTypes: productTypes, genders: genders)
        return snapshot.productTypes == fp.productTypes && snapshot.genders == fp.genders
    }

    /// Encodes the (capped, ~15 item) snapshot and hands the file write to a
    /// background queue, so no disk I/O happens on the main thread. Callers
    /// debounce this (see `FeedViewModel.persistFeedWarmCache`) so a burst of
    /// swipes produces one write.
    static func save(items: ArraySlice<Item>, productTypes: Set<ProductType>, genders: Set<GenderFilter>) {
        let fp = fingerprint(productTypes: productTypes, genders: genders)
        let capped = Array(items.prefix(maxItems))
        let snapshot = Snapshot(items: capped, productTypes: fp.productTypes, genders: fp.genders)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        writeQueue.async {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Returns cached items when the file exists, decodes, fingerprint matches, and at least one item is present.
    static func loadIfValid(productTypes: Set<ProductType>, genders: Set<GenderFilter>) -> [Item]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        guard matches(snapshot, productTypes: productTypes, genders: genders) else { return nil }
        guard !snapshot.items.isEmpty else { return nil }
        return snapshot.items
    }

    /// Removes the on-disk warm snapshot (e.g. from Settings). Queued behind
    /// any pending write so a late save can't resurrect it.
    static func clear() {
        writeQueue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
