import Foundation
import Observation

@Observable
@MainActor
final class BrandProductsViewModel {
    let brandName: String
    private let pageSize = 24

    var items: [Item] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    private var nextPage = 1
    private var hasMorePages = true

    /// Distinct labels (subcategory preferred, else category) seen in loaded data.
    private(set) var facetCategories: [String] = []
    private(set) var facetGenders: [String] = []

    var selectedCategory: String? = nil
    var selectedGender: String? = nil

    init(brandName: String) {
        self.brandName = brandName
    }

    /// Prefer subcategory for “socks / t‑shirt” style facets; fall back to category.
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

    /// One-time wide fetch to populate category/gender chips for this brand (does not replace `items`).
    func loadFacetsProbe() async {
        do {
            let response = try await ItemService.fetchItemsPage(
                page: 1,
                limit: 100,
                category: nil,
                brand: brandName,
                search: nil,
                gender: nil,
                productType: nil
            )
            mergeFacets(from: response.items)
        } catch {
            // Ignore: filters still work from facets merged during normal paging.
        }
    }

    func loadInitial() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        nextPage = 1
        hasMorePages = true
        do {
            let response = try await ItemService.fetchItemsPage(
                page: 1,
                limit: pageSize,
                category: selectedCategory,
                brand: brandName,
                search: nil,
                gender: selectedGender,
                productType: nil
            )
            items = response.items
            mergeFacets(from: response.items)
            nextPage = 2
            if let totalPages = response.pagination?.totalPages, let p = response.pagination?.page {
                hasMorePages = p < totalPages
            } else {
                hasMorePages = response.items.count >= pageSize
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears items and reloads after filter change.
    func reloadWithCurrentFilters() async {
        items = []
        nextPage = 1
        hasMorePages = true
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

    func loadMoreIfNeeded() async {
        guard hasMorePages, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        errorMessage = nil
        defer { isLoadingMore = false }
        do {
            let response = try await ItemService.fetchItemsPage(
                page: nextPage,
                limit: pageSize,
                category: selectedCategory,
                brand: brandName,
                search: nil,
                gender: selectedGender,
                productType: nil
            )
            if response.items.isEmpty {
                hasMorePages = false
                return
            }
            items.append(contentsOf: response.items)
            mergeFacets(from: response.items)
            nextPage += 1
            if let totalPages = response.pagination?.totalPages, let p = response.pagination?.page {
                hasMorePages = p < totalPages
            } else {
                hasMorePages = response.items.count >= pageSize
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
