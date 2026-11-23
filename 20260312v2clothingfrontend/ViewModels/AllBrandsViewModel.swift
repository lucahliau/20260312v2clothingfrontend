import Foundation
import Observation

/// Backs the "All brands" A–Z list: one request for every brand (the catalog
/// has a few hundred), filtered and sectioned locally.
@Observable
@MainActor
final class AllBrandsViewModel {
    /// Brands with fewer products than this are hidden unless "show all" is on.
    static let smallBrandThreshold = 10

    struct LetterSection: Identifiable {
        let letter: String
        let brands: [BrandInfo]
        var id: String { letter }
    }

    private(set) var brands: [BrandInfo] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false
    var searchText = ""

    @ObservationIgnored private var generation = 0

    /// Brands matching the quick-search field (case/diacritic-insensitive substring).
    var filteredBrands: [BrandInfo] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return brands }
        return brands.filter {
            $0.brand.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// A–Z sections; anything not starting with a letter goes under "#".
    var sections: [LetterSection] {
        var buckets: [String: [BrandInfo]] = [:]
        for brand in filteredBrands {
            buckets[Self.sectionLetter(for: brand.brand), default: []].append(brand)
        }
        return buckets.keys
            .sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs < rhs
            }
            .map { key in
                LetterSection(
                    letter: key,
                    brands: (buckets[key] ?? []).sorted {
                        $0.brand.localizedCaseInsensitiveCompare($1.brand) == .orderedAscending
                    }
                )
            }
    }

    static func sectionLetter(for name: String) -> String {
        let folded = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .uppercased()
        guard let first = folded.first, first.isLetter, first.isASCII else { return "#" }
        return String(first)
    }

    /// Loads the list. `hideSmall` maps to `minProducts=10` server-side. A newer
    /// call (e.g. the toggle flipped mid-load) supersedes an older response.
    func load(hideSmall: Bool) async {
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        do {
            let result = try await BrandService.fetchAllBrands(
                minProducts: hideSmall ? Self.smallBrandThreshold : nil
            )
            guard current == generation else { return }
            brands = result
            hasLoaded = true
        } catch {
            guard current == generation else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
