import Foundation

/// Filters catalog items using the same URL chains as the UI (`imageUrlPairs` vs original JPEGs).
enum ItemImageDisplayability {
    /// Feed-style lists: require the **primary** URL (nobg when enabled) to decode so the UI never swaps to fallback-only (aspect-ratio flicker).
    static func canRenderFeedStyleImage(for item: Item) async -> Bool {
        guard let pair = item.imageUrlPairs.first, let u = URL(string: pair.primary) else { return false }
        return await ImageCacheService.shared.loadImage(from: u) != nil
    }

    /// True if primary or fallback loads; use only when fallback-only display is acceptable.
    static func canRenderFeedStyleImageAllowingFallback(for item: Item) async -> Bool {
        guard let pair = item.imageUrlPairs.first else { return false }
        if let u = URL(string: pair.primary), await ImageCacheService.shared.loadImage(from: u) != nil {
            return true
        }
        if let fb = pair.fallback, let u = URL(string: fb), await ImageCacheService.shared.loadImage(from: u) != nil {
            return true
        }
        return false
    }

    /// Matches explore featured collages and brand product grids (`firstOriginalImageURL` + second).
    static func canRenderOriginalStyleImage(for item: Item) async -> Bool {
        if let u = item.firstOriginalImageURL, await ImageCacheService.shared.loadImage(from: u) != nil {
            return true
        }
        if let u = item.secondOriginalImageURL, await ImageCacheService.shared.loadImage(from: u) != nil {
            return true
        }
        return false
    }

    static func filterFeedStyleItems(_ items: [Item]) async -> [Item] {
        await filterItems(items, check: canRenderFeedStyleImage(for:))
    }

    static func filterOriginalStyleItems(_ items: [Item]) async -> [Item] {
        await filterItems(items, check: canRenderOriginalStyleImage(for:))
    }

    /// Drops history rows whose embedded `item` fails feed-style decode; keeps rows without an embedded item.
    static func filterSwipeRecords(_ records: [SwipeRecord]) async -> [SwipeRecord] {
        var results: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for record in records {
                guard let item = record.item else { continue }
                group.addTask {
                    (record.id, await canRenderFeedStyleImage(for: item))
                }
            }
            for await (id, ok) in group {
                results[id] = ok
            }
        }
        return records.filter { r in
            guard r.item != nil else { return true }
            return results[r.id] == true
        }
    }

    private static func filterItems(_ items: [Item], check: @escaping (Item) async -> Bool) async -> [Item] {
        guard !items.isEmpty else { return [] }
        var results: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for item in items {
                group.addTask {
                    (item.id, await check(item))
                }
            }
            for await (id, ok) in group {
                results[id] = ok
            }
        }
        return items.filter { results[$0.id] == true }
    }
}
