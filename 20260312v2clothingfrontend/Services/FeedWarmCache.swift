import Foundation

/// Persists the first few feed items + filter fingerprint for instant cold-start UI.
enum FeedWarmCache {
    private static let maxItems = 5
    private static let fileName = "feed_warm_cache.json"

    private struct Snapshot: Codable {
        let items: [Item]
        let productTypes: [String]
        let genders: [String]
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("FeedWarmCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

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

    static func save(items: [Item], productTypes: Set<ProductType>, genders: Set<GenderFilter>) {
        let fp = fingerprint(productTypes: productTypes, genders: genders)
        let capped = Array(items.prefix(maxItems))
        let snapshot = Snapshot(items: capped, productTypes: fp.productTypes, genders: fp.genders)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best effort
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
}
