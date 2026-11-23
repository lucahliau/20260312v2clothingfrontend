import Foundation
import Observation

@Observable
@MainActor
final class ExploreViewModel {
    var searchText = ""

    var featuredBrands: [BrandInfo] = []
    /// Preview items for collage, keyed by exact brand name.
    var featuredPreviewItems: [String: [Item]] = [:]

    /// Brands the user saved (hearted) from brand pages.
    var savedBrands: [BrandInfo] = []

    var brandResults: [BrandInfo] = []
    var productResults: [Item] = []

    var isLoadingFeatured = false
    var isSearching = false
    /// True while a *subsequent* page of product results is loading (drives the
    /// bottom "loading more" skeleton without blocking what's already shown).
    private(set) var isLoadingMoreProducts = false
    /// Whether more product result pages remain for the active query.
    private(set) var searchHasMore = false
    var errorMessage: String?
    /// Set when the featured rail failed to load — the section shows this with
    /// a Retry button instead of pretending there are no featured brands.
    private(set) var featuredErrorMessage: String?
    /// Set when a further page of product results failed; shown under the grid
    /// with a Retry (scrolling alone no longer silently swallows it).
    private(set) var loadMoreErrorMessage: String?

    private var searchDebounceTask: Task<Void, Never>?
    private var searchGeneration = 0

    /// Page size for product-search requests — small enough for a fast first
    /// paint, paged via infinite scroll (mirrors the brand product grid).
    private static let searchPageSize = 60
    /// Brand search is a cheap autocomplete: a short list, not the whole catalog.
    private static let brandSearchLimit = 20
    /// Load the next product page when a cell within this many rows of the end appears.
    private let searchNearEndWindow = 12
    private var searchCurrentPage = 1
    /// The query the loaded product pages belong to, so pagination stays consistent.
    private var activeProductQuery = ""

    private static let featuredBrandLimit = 5

    /// Refreshes the saved-brands strip. Silent on failure (the strip simply
    /// keeps its last known contents) — called on every Explore appearance so
    /// a heart toggled on a brand page shows up when the user comes back.
    func refreshSavedBrands() async {
        do {
            savedBrands = try await BrandService.fetchFavoriteBrands()
        } catch {
            // Non-fatal: keep whatever we had.
        }
    }

    /// The server just became reachable again: load whatever failed while it
    /// was away (featured rail, saved strip, the active search).
    func reloadAfterServerRecovery() async {
        errorMessage = nil
        async let saved: Void = refreshSavedBrands()
        await loadFeaturedIfNeeded()
        await saved
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           brandResults.isEmpty, productResults.isEmpty {
            onSearchTextChanged()
        }
    }

    func loadFeaturedIfNeeded() async {
        guard featuredBrands.isEmpty else { return }
        await loadFeatured()
    }

    /// Pull-to-refresh: reloads the featured rail and saved strip, or re-runs
    /// the active search. Existing content stays on screen while it loads.
    func refresh() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            async let saved: Void = refreshSavedBrands()
            await loadFeatured()
            await saved
        } else {
            searchDebounceTask?.cancel()
            searchGeneration += 1
            await performSearch(query: trimmed, generation: searchGeneration)
        }
    }

    /// Fetches the featured rail. The skeleton only shows when nothing is on
    /// screen yet, so a refresh never blanks the section.
    func loadFeatured() async {
        guard !isLoadingFeatured else { return }
        isLoadingFeatured = true
        featuredErrorMessage = nil
        defer { isLoadingFeatured = false }
        do {
            let entries = try await BrandService.fetchFeaturedBrands(limit: Self.featuredBrandLimit)
            featuredBrands = entries.map {
                BrandInfo(brand: $0.brand, productCount: $0.productCount)
            }
            featuredPreviewItems = Dictionary(
                uniqueKeysWithValues: entries.map { ($0.brand, $0.items) }
            )
            prefetchFeaturedCollageImages()
        } catch {
            // Shown inline (with Retry) when the rail is empty; a failed refresh
            // over existing content keeps what's there.
            featuredErrorMessage = error.localizedDescription
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

    func onSearchTextChanged() {
        searchDebounceTask?.cancel()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            brandResults = []
            productResults = []
            isSearching = false
            searchHasMore = false
            loadMoreErrorMessage = nil
            activeProductQuery = ""
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

    /// Loads page 1 of products + a short brand list and renders immediately.
    /// No upfront "decode every image" pass (the old `filterFeedStyleItems` over
    /// `fetchAllItemsPages` downloaded the whole result set before first paint);
    /// each cell now validates its own image lazily and drops itself on a 404.
    private func performSearch(query: String, generation: Int) async {
        errorMessage = nil
        loadMoreErrorMessage = nil
        do {
            async let brandsTask = BrandService.fetchBrands(q: query, limit: Self.brandSearchLimit)
            async let pageTask = ItemService.fetchItemsPage(page: 1, limit: Self.searchPageSize, search: query)
            let (brands, page) = try await (brandsTask, pageTask)
            guard generation == searchGeneration else { return }
            brandResults = brands
            productResults = page.items
            activeProductQuery = query
            searchCurrentPage = 1
            searchHasMore = (page.pagination?.totalPages ?? 1) > 1
            prefetchProductImages(page.items)
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.localizedDescription
            brandResults = []
            productResults = []
            searchHasMore = false
        }
        guard generation == searchGeneration else { return }
        isSearching = false
        // One event per completed (non-superseded) search — query length, not
        // the raw text (privacy), plus result count for zero-result-rate.
        AnalyticsManager.shared.track(
            "search",
            metadata: ["len": String(query.count), "results": String(brandResults.count + productResults.count)]
        )
    }

    /// Infinite scroll for the product results grid (mirrors the brand grid).
    func loadMoreProductResultsIfNeeded(currentIndex: Int) async {
        // After a failure, wait for the explicit Retry instead of re-firing on
        // every cell appearance.
        guard loadMoreErrorMessage == nil else { return }
        guard currentIndex >= productResults.count - searchNearEndWindow else { return }
        await loadNextProductPage()
    }

    func retryLoadMoreProducts() async {
        loadMoreErrorMessage = nil
        await loadNextProductPage()
    }

    private func loadNextProductPage() async {
        guard searchHasMore, !isSearching, !isLoadingMoreProducts else { return }
        isLoadingMoreProducts = true
        defer { isLoadingMoreProducts = false }
        let nextPage = searchCurrentPage + 1
        let query = activeProductQuery
        let generation = searchGeneration
        do {
            let page = try await ItemService.fetchItemsPage(page: nextPage, limit: Self.searchPageSize, search: query)
            // Bail if the query changed or this search was superseded mid-flight.
            guard generation == searchGeneration, query == activeProductQuery else { return }
            let known = Set(productResults.map(\.id))
            let fresh = page.items.filter { !known.contains($0.id) }
            productResults.append(contentsOf: fresh)
            searchCurrentPage = nextPage
            searchHasMore = (page.pagination?.totalPages ?? nextPage) > nextPage
            prefetchProductImages(fresh)
        } catch {
            guard generation == searchGeneration, query == activeProductQuery else { return }
            // Keep what's shown; the grid footer offers a Retry.
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    /// Drops a result whose primary AND fallback images both 404'd (wired from
    /// `CachedAsyncImage.onUnrecoverableHTTP404`), so a dead row leaves no
    /// permanent skeleton. Replaces the old upfront displayability filter.
    func removeProductResult(id: String) {
        productResults.removeAll { $0.id == id }
    }

    private func prefetchProductImages(_ items: [Item]) {
        for item in items.prefix(24) {
            guard let pair = item.imageUrlPairs.first, let url = URL(string: pair.primary) else { continue }
            ImageCacheService.shared.preload(from: url)
        }
    }
}
