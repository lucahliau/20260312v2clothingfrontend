import Foundation

/// Warms the image cache for upcoming brand-grid cells. Mirrors the chunked task-group
/// pattern in `ExploreViewModel.prefetchCollageImagesAggressively`.
enum BrandImagePrefetcher {
    /// Prefetches the `firstOriginalImageURL` of each item, capped at `maxURLs` distinct URLs,
    /// in chunks of `chunkSize` concurrent requests to stay under URLSession's 6-per-host cap.
    static func prefetch(items: [Item], maxURLs: Int = 30, chunkSize: Int = 5) {
        var urls: [URL] = []
        var seen = Set<String>()
        for item in items {
            guard let u = item.firstOriginalImageURL else { continue }
            let key = u.absoluteString
            guard seen.insert(key).inserted else { continue }
            urls.append(u)
            if urls.count >= maxURLs { break }
        }
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await loadInChunks(urls: urls, chunkSize: chunkSize)
        }
    }

    private static func loadInChunks(urls: [URL], chunkSize: Int) async {
        var i = urls.startIndex
        while i < urls.endIndex {
            let j = urls.index(i, offsetBy: chunkSize, limitedBy: urls.endIndex) ?? urls.endIndex
            await withTaskGroup(of: Void.self) { group in
                var k = i
                while k < j {
                    let url = urls[k]
                    group.addTask {
                        _ = await ImageCacheService.shared.loadImage(from: url)
                    }
                    k = urls.index(after: k)
                }
            }
            i = j
        }
    }
}
