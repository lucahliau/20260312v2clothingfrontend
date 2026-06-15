import Foundation
import Observation

@Observable
@MainActor
final class BrandProductsViewModel {
    let brandName: String

    /// Items currently rendered, after client-side sort.
    var items: [Item] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    /// Non-blocking error for "next page failed" — surfaced as a retry toast, not a full-screen alert.
    var paginationErrorMessage: String?

    /// Distinct labels (subcategory preferred, else category) seen in loaded data.
    private(set) var facetCategories: [String] = []
    private(set) var facetGenders: [String] = []

    var selectedCategory: String? = nil
    var selectedGender: String? = nil
    var selectedPriceRange: BrandPriceRange? = nil
    var sortOption: BrandSortOption = .featured

    /// Page size for `/items` requests. Small enough for a fast first paint, large enough
    /// to avoid hammering pagination on long catalogs.
    private let pageSize = 60
    /// Trigger `loadMoreIfNeeded` / prefetch when a cell within this many rows of the end appears.
    private let nearEndWindow = 12

    private var currentPage = 1
    private(set) var hasMore = false

    /// Server-order items, before sort is applied. Sort runs over this snapshot so toggling
    /// sort options is deterministic and cheap.
    private var rawItems: [Item] = []

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

    /// Prefer subcategory for "socks / t-shirt" style facets; fall back to category.
    static func facetCategoryLabel(for item: Item) -> String? {
        if let s = item.subcategory?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if let c = item.category?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        return nil
    }

    private func mergeFacets(from newItems: [Item]) {
        var cats = Set(facetCategories)
        var gens = Set(facetGenders)
        for item in newItems {
            if let f = Self.facetCategoryLabel(for: item) {
                cats.insert(f)
            }
            if let g = item.gender?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                gens.insert(g)
            }
        }
        facetCategories = cats.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        facetGenders = gens.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func applySort() {
        items = sortOption.apply(to: rawItems)
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        paginationErrorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await ItemService.fetchItemsPage(
                page: 1,
                limit: pageSize,
                category: selectedCategory,
                brand: brandName,
                search: nil,
                gender: selectedGender,
                productType: nil,
                minPrice: selectedPriceRange?.minPrice,
                maxPrice: selectedPriceRange?.maxPrice
            )
            rawItems = response.items
            currentPage = 1
            hasMore = (response.pagination?.totalPages ?? 1) > 1
            mergeFacets(from: response.items)
            applySort()
            BrandImagePrefetcher.prefetch(items: response.items)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentIndex: Int) async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        guard currentIndex >= items.count - nearEndWindow else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        isLoadingMore = true
        defer { isLoadingMore = false }
        let nextPage = currentPage + 1
        do {
            let response = try await ItemService.fetchItemsPage(
                page: nextPage,
                limit: pageSize,
                category: selectedCategory,
                brand: brandName,
                search: nil,
                gender: selectedGender,
                productType: nil,
                minPrice: selectedPriceRange?.minPrice,
                maxPrice: selectedPriceRange?.maxPrice
            )
            // Dedupe by id in case the backend ever returns overlap.
            let known = Set(rawItems.map(\.id))
            let fresh = response.items.filter { !known.contains($0.id) }
            rawItems.append(contentsOf: fresh)
            currentPage = nextPage
            hasMore = (response.pagination?.totalPages ?? nextPage) > nextPage
            mergeFacets(from: fresh)
            applySort()
            BrandImagePrefetcher.prefetch(items: fresh)
        } catch {
            paginationErrorMessage = error.localizedDescription
        }
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
        rawItems.removeAll { $0.id == id }
        items.removeAll { $0.id == id }
    }

    /// Clears items and reloads after filter change.
    func reloadWithCurrentFilters() async {
        rawItems = []
        items = []
        currentPage = 1
        hasMore = false
        paginationErrorMessage = nil
        await loadInitial()
    }

    func setCategoryFilter(_ value: String?) {
        let normalized = value?.isEmpty == true ? nil : value
        guard normalized != selectedCategory else { return }
        selectedCategory = normalized
        Task { await reloadWithCurrentFilters() }
    }

    func setGenderFilter(_ value: String?) {
        let normalized = value?.isEmpty == true ? nil : value
        guard normalized != selectedGender else { return }
        selectedGender = normalized
        Task { await reloadWithCurrentFilters() }
    }

    func setPriceFilter(_ value: BrandPriceRange?) {
        guard value != selectedPriceRange else { return }
        selectedPriceRange = value
        Task { await reloadWithCurrentFilters() }
    }

    func setSortOption(_ value: BrandSortOption) {
        guard value != sortOption else { return }
        sortOption = value
        applySort()
    }
}
