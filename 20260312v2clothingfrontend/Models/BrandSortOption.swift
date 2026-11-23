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

/// Sort options for product grids (brand page, search results). Applied
/// SERVER-side via `sort=` on `GET /items`, so the order is correct across the
/// whole result set rather than just the pages loaded so far.
///
/// `.featured` is the server's default order (newest first on a brand page,
/// relevance for a text search); the old separate "Newest" option was identical
/// to it on brand pages and has been removed.
enum BrandSortOption: String, CaseIterable, Identifiable, Sendable {
    case featured
    case priceAsc
    case priceDesc

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .featured: return "Newest"
        case .priceAsc: return "Price: Low to High"
        case .priceDesc: return "Price: High to Low"
        }
    }

    /// Value for the `sort` query parameter; `nil` keeps the server default.
    var serverValue: String? {
        switch self {
        case .featured: return nil
        case .priceAsc: return "price_asc"
        case .priceDesc: return "price_desc"
        }
    }
}
