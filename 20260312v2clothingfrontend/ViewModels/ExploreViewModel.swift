import Foundation
import Observation

@Observable
@MainActor
final class ExploreViewModel {
    var searchText = ""

    var featuredBrands: [BrandInfo] = []
    /// Preview items for collage, keyed by exact brand name.
    var featuredPreviewItems: [String: [Item]] = [:]

    var brandResults: [BrandInfo] = []
    var productResults: [Item] = []

    var isLoadingFeatured = false
    var isSearching = false
    var errorMessage: String?

    private var searchDebounceTask: Task<Void, Never>?
    private var searchGeneration = 0

    /// Featured brands must exceed this many products (API `productCount`).
    private let minFeaturedBrandProductCount = 100
    /// Max brands from explore endpoint to filter for large catalogs.
    private let exploreBrandSampleLimit = 50
    /// Pool size to pick varied collage thumbnails from.
    private let collageItemPoolLimit = 48

    func loadFeaturedIfNeeded() async {
        guard featuredBrands.isEmpty, !isLoadingFeatured else { return }
        isLoadingFeatured = true
        errorMessage = nil
        defer { isLoadingFeatured = false }
        do {
            let brands = try await BrandService.fetchExploreBrands(limit: exploreBrandSampleLimit)
            let largeEnough = brands.filter { $0.productCount > minFeaturedBrandProductCount }
            featuredBrands = Array(largeEnough.prefix(2))
            featuredPreviewItems = [:]
            let poolLimit = collageItemPoolLimit
            try await withThrowingTaskGroup(of: (String, [Item]).self) { group in
                for info in featuredBrands {
                    group.addTask {
                        let page = try await ItemService.fetchItemsPage(
                            page: 1,
                            limit: poolLimit,
                            brand: info.brand,
                            search: nil
                        )
                        let picked = Self.variedCollageItems(from: page.items, count: 4)
                        return (info.brand, picked)
                    }
                }
                for try await pair in group {
                    featuredPreviewItems[pair.0] = pair.1
                }
            }
            prefetchFeaturedCollageImages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prefetchFeaturedCollageImages() {
        var urls: [URL] = []
        var seen = Set<String>()
        outer: for (_, items) in featuredPreviewItems {
            for item in items {
                if let u = item.firstOriginalImageURL, seen.insert(u.absoluteString).inserted {
                    urls.append(u)
                }
                if urls.count >= 24 { break outer }
            }
        }
        for u in urls {
            ImageCacheService.shared.preload(from: u)
        }
        Task.detached(priority: .utility) {
            await Self.prefetchCollageImagesAggressively(urls: urls)
        }
    }

    private nonisolated static func prefetchCollageImagesAggressively(urls: [URL]) async {
        let chunkSize = 5
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

    /// Picks distinct items spread across the pool (shuffle) so collage cells are not four near-identical listings.
    private nonisolated static func variedCollageItems(from items: [Item], count: Int) -> [Item] {
        guard !items.isEmpty else { return [] }
        let deduped = Array(Dictionary(grouping: items, by: \.id).values.compactMap(\.first))
        guard deduped.count > count else { return Array(deduped.shuffled()) }
        return Array(deduped.shuffled().prefix(count))
    }

    func onSearchTextChanged() {
        searchDebounceTask?.cancel()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            brandResults = []
            productResults = []
            isSearching = false
            searchGeneration += 1
            return
        }
        isSearching = true
        searchGeneration += 1
        let generation = searchGeneration
        let query = trimmed
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch(query: query, generation: generation)
        }
    }

    private func performSearch(query: String, generation: Int) async {
        errorMessage = nil
        do {
            async let brandsTask = BrandService.fetchBrands(q: query, limit: 10)
            async let itemsTask = ItemService.fetchItemsPage(page: 1, limit: 20, search: query)
            let (brands, page) = try await (brandsTask, itemsTask)
            guard generation == searchGeneration else { return }
            brandResults = brands
            productResults = page.items
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.localizedDescription
            brandResults = []
            productResults = []
        }
        guard generation == searchGeneration else { return }
        isSearching = false
    }
}
