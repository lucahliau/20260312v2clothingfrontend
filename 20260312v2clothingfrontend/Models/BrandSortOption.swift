import Foundation

/// Price buckets for the brand-products grid. Applied server-side via
/// `minPrice`/`maxPrice` on `/items` so pagination stays correct.
enum BrandPriceRange: String, CaseIterable, Identifiable, Sendable {
    case under50
    case from50to100
    case from100to200
    case over200

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .under50: return "Under $50"
        case .from50to100: return "$50 – $100"
        case .from100to200: return "$100 – $200"
        case .over200: return "$200+"
        }
    }

    var minPrice: Double? {
        switch self {
        case .under50: return nil
        case .from50to100: return 50
        case .from100to200: return 100
        case .over200: return 200
        }
    }

    var maxPrice: Double? {
        switch self {
        case .under50: return 50
        case .from50to100: return 100
        case .from100to200: return 200
        case .over200: return nil
        }
    }
}

/// Sort options for the brand-products grid. Applied client-side over the items loaded so far.
enum BrandSortOption: String, CaseIterable, Identifiable, Sendable {
    case featured
    case priceAsc
    case priceDesc
    case newest

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .featured: return "Featured"
        case .priceAsc: return "Price: Low to High"
        case .priceDesc: return "Price: High to Low"
        case .newest: return "Newest"
        }
    }

    /// `.featured` preserves the server's order (which is what the user gets with no sort applied).
    func apply(to items: [Item]) -> [Item] {
        switch self {
        case .featured:
            return items
        case .priceAsc:
            return items.sorted { lhs, rhs in
                switch (lhs.priceDouble, rhs.priceDouble) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return false
                }
            }
        case .priceDesc:
            return items.sorted { lhs, rhs in
                switch (lhs.priceDouble, rhs.priceDouble) {
                case let (l?, r?): return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return false
                }
            }
        case .newest:
            // ISO-8601 strings sort lexicographically; falls back to updatedAt then keeps order.
            return items.sorted { lhs, rhs in
                let l = lhs.createdAt ?? lhs.updatedAt ?? ""
                let r = rhs.createdAt ?? rhs.updatedAt ?? ""
                return l > r
            }
        }
    }
}
