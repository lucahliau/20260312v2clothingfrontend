import Foundation
import Observation

@Observable
@MainActor
final class BrandProductsViewModel {
    let brandName: String

    /// Items currently rendered, in server order (sorting is server-side).
    var items: [Item] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    /// Non-blocking error for "next page failed" — surfaced as a retry toast, not a full-screen alert.
    var paginationErrorMessage: String?

    /// Set when the first page failed, so the grid shows a Retry instead of
    /// claiming the brand has no products.
    private(set) var loadErrorMessage: String?

    /// Distinct `category` values seen in loaded data. The server normalises
    /// `category` to a small canonical set and filters on exactly that column,
    /// so the facet shown and the `category=` query always agree.
    private(set) var facetCategories: [String] = []
    private(set) var facetGenders: [String] = []

    var selectedCategory: String? = nil
    var selectedGender: String? = nil
    var selectedPriceRange: BrandPriceRange? = nil
    /// Only items the retailer currently discounts (`onSale=true`).
    var onSaleOnly = false
    var sortOption: BrandSortOption = .featured

    /// Page size for `/items` requests. Small enough for a fast first paint, large enough
    /// to avoid hammering pagination on long catalogs.
    private let pageSize = 60
    /// Trigger `loadMoreIfNeeded` / prefetch when a cell within this many rows of the end appears.
    private let nearEndWindow = 12

    private var currentPage = 1
    private(set) var hasMore = false
    /// `pagination.total` for the current filters; `nil` until the first page lands.
    private(set) var totalCount: Int?
    private var hasLoadedOnce = false

    /// Bumped on every reload. A response (first page or load-more) whose
    /// generation is stale is discarded, so a filter/sort change made while a
    /// request is in flight always wins and old pages can't be appended.
    private var loadGeneration = 0
    private var reloadTask: Task<Void, Never>?

    /// Whether the user has saved (hearted) this brand.
    private(set) var isSavedBrand = false
    private var isSavingBrand = false

    init(brandName: String) {
        self.brandName = brandName
    }

    /// Fetches whether this brand is in the user's saved brands. Failures are
    /// silent — the heart just starts unsaved.
    func loadSavedBrandState() async {
        do {
            let favorites = try await BrandService.fetchFavoriteBrands()
            isSavedBrand = favorites.contains {
                $0.brand.caseInsensitiveCompare(brandName) == .orderedSame
            }
        } catch {
            // Non-fatal: keep the default unsaved state.
        }
    }

    func toggleSavedBrand() async {
        guard !isSavingBrand else { return }
        isSavingBrand = true
        defer { isSavingBrand = false }
        let target = !isSavedBrand
        isSavedBrand = target
        do {
            try await BrandService.setFavoriteBrand(brandName, favorite: target)
        } catch {
            isSavedBrand = !target
            errorMessage = error.localizedDescription
        }
    }

    private func mergeFacets(from newItems: [Item]) {
        var cats = Set(facetCategories)
        var gens = Set(facetGenders)
        for item in newItems {
            if let c = item.category?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                cats.insert(c)
            }
            if let g = item.gender?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                gens.insert(g)
            }
        }
        facetCategories = cats.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        facetGenders = gens.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func fetchPage(_ page: Int) async throws -> PaginatedItemsResponse {
        try await ItemService.fetchItemsPage(
            page: page,
            limit: pageSize,
            category: selectedCategory,
            brand: brandName,
            search: nil,
            gender: selectedGender,
            productType: nil,
            minPrice: selectedPriceRange?.minPrice,
            maxPrice: selectedPriceRange?.maxPrice,
            onSale: onSaleOnly,
            sort: sortOption.serverValue
        )
    }

    /// First appearance only — re-appearing must not reset the grid.
    func loadInitial() async {
        guard !hasLoadedOnce, !isLoading else { return }
        await reload()
    }

    /// Loads page 1 for the current filters + sort, superseding anything in flight.
    func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        loadErrorMessage = nil
        paginationErrorMessage = nil
        do {
            let response = try await fetchPage(1)
            guard generation == loadGeneration else { return }
            items = response.items
            currentPage = 1
            hasMore = (response.pagination?.totalPages ?? 1) > 1
            totalCount = response.pagination?.total
            hasLoadedOnce = true
            mergeFacets(from: response.items)
            BrandImagePrefetcher.prefetch(items: response.items)
        } catch {
            guard generation == loadGeneration else { return }
            if !error.isCancellation {
                loadErrorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func loadMoreIfNeeded(currentIndex: Int) async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        // After a failed page, wait for the toast's Retry rather than re-firing
        // on every cell appearance.
        guard paginationErrorMessage == nil else { return }
        guard currentIndex >= items.count - nearEndWindow else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        let nextPage = currentPage + 1
        do {
            let response = try await fetchPage(nextPage)
            // Filters or sort changed mid-flight: this page belongs to the old query.
            guard generation == loadGeneration else { return }
            // Dedupe by id: offset pagination can overlap when the catalog shifts.
            let known = Set(items.map(\.id))
            let fresh = response.items.filter { !known.contains($0.id) }
            items.append(contentsOf: fresh)
            currentPage = nextPage
            hasMore = (response.pagination?.totalPages ?? nextPage) > nextPage
            if let total = response.pagination?.total { totalCount = total }
            mergeFacets(from: fresh)
            BrandImagePrefetcher.prefetch(items: fresh)
        } catch {
            guard generation == loadGeneration else { return }
            if !error.isCancellation {
                paginationErrorMessage = error.localizedDescription
            }
        }
        isLoadingMore = false
    }

    /// Hand the next-window items to the prefetcher when the user is nearing the bottom.
    func prefetchUpcoming(currentIndex: Int) {
        guard currentIndex >= items.count - nearEndWindow, currentIndex < items.count else { return }
        let upcoming = Array(items.suffix(from: currentIndex))
        BrandImagePrefetcher.prefetch(items: upcoming, maxURLs: 18)
    }

    /// Retry the page that failed (called from the bottom error toast).
    func retryPagination() async {
        guard paginationErrorMessage != nil else { return }
        paginationErrorMessage = nil
        await loadNextPage()
    }

    /// Drops an item whose primary AND fallback URLs both 404'd. Called from `CachedAsyncImage.onUnrecoverableHTTP404`.
    /// The caller is responsible for not invoking this on the item currently shown in the detail sheet.
    func removeItem(id: String) {
        items.removeAll { $0.id == id }
    }

    /// Clears the grid and reloads from page 1 after a filter or sort change.
    /// Cancels the in-flight request; the generation counter covers the rest.
    private func scheduleReload() {
        reloadTask?.cancel()
        items = []
        currentPage = 1
        hasMore = false
        totalCount = nil
        reloadTask = Task { await reload() }
    }

    func setCategoryFilter(_ value: String?) {
        let normalized = value?.isEmpty == true ? nil : value
        guard normalized != selectedCategory else { return }
        selectedCategory = normalized
        scheduleReload()
    }

    func setGenderFilter(_ value: String?) {
        let normalized = value?.isEmpty == true ? nil : value
        guard normalized != selectedGender else { return }
        selectedGender = normalized
        scheduleReload()
    }

    func setPriceFilter(_ value: BrandPriceRange?) {
        guard value != selectedPriceRange else { return }
        selectedPriceRange = value
        scheduleReload()
    }

    func setOnSaleOnly(_ value: Bool) {
        guard value != onSaleOnly else { return }
        onSaleOnly = value
        scheduleReload()
    }

    /// Sorting is server-side, so a change reloads from page 1.
    func setSortOption(_ value: BrandSortOption) {
        guard value != sortOption else { return }
        sortOption = value
        scheduleReload()
    }

    var hasActiveFilters: Bool {
        selectedCategory != nil || selectedGender != nil || selectedPriceRange != nil || onSaleOnly
    }

    func clearFilters() {
        guard hasActiveFilters else { return }
        selectedCategory = nil
        selectedGender = nil
        selectedPriceRange = nil
        onSaleOnly = false
        scheduleReload()
    }

    /// Love/Like from the grid's context menu. Failures are surfaced instead of
    /// being dropped (offline swipes are queued by `SwipeService`, not errors).
    func recordSwipe(itemId: String, type: SwipeType) async {
        do {
            try await SwipeService.recordSwipe(itemId: itemId, type: type)
        } catch {
            errorMessage = "Couldn't save that. \(error.localizedDescription)"
        }
    }
}
