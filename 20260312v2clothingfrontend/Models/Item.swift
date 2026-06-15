import Foundation

// MARK: - Filter Enums

enum ProductType: String, CaseIterable, Sendable {
    case tops, bottoms, bags, accessories, jackets, other
    var displayName: String { rawValue.capitalized }
}

enum GenderFilter: String, CaseIterable, Sendable {
    case male, female, unisex
    var displayName: String { rawValue.capitalized }

    /// Feed default from profile (`SettingsViewModel.gender`); empty set means no API gender filter (all).
    static func defaultSelection(forProfileGender profileGender: String?) -> Set<GenderFilter> {
        let g = profileGender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !g.isEmpty else { return [] }
        switch g {
        case "Male": return [.male, .unisex]
        case "Female": return [.female, .unisex]
        default: return []
        }
    }
}

// MARK: - Item

struct Item: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let brand: String?
    let category: String?
    let subcategory: String?
    let price: String?
    let currency: String?
    let imageUrl: String?
    let images: [String]?
    let colors: [String]?
    let sizes: [String]?
    let tags: [String]?
    let gender: String?
    let productType: String?
    let sourceUrl: String?
    let retailer: String?
    let externalId: String?
    let manufacturerCode: String?
    let lastVerifiedAt: String?
    let active: Bool?
    let createdAt: String?
    let updatedAt: String?

    /// Combined image URLs: primary imageUrl first, then images array.
    var imageUrls: [String] {
        let primary = imageUrl.map { [$0] } ?? []
        let additional = images ?? []
        return primary + additional
    }

    /// Image URL pairs for display: primary (nobg when enabled) with fallback to original if primary fails.
    var imageUrlPairs: [(primary: String, fallback: String?)] {
        let raw = imageUrls
        if Item.useBackgroundRemovedImages {
            return raw.map { (primary: $0.imageUrlNoBg.normalizedAsHTTPURLString, fallback: $0.normalizedAsHTTPURLString) }
        }
        return raw.map { (primary: $0.normalizedAsHTTPURLString, fallback: nil) }
    }

    /// Set to `true` to use background-removed (-nobg.png) variants, falling back to original if nobg missing.
    static var useBackgroundRemovedImages = true

    /// First catalog image URL (original asset, not `-nobg`). Use for explore collages and brand grids when full product photos are preferred.
    var firstOriginalImageURL: URL? {
        guard let s = imageUrls.first else { return nil }
        return URL(string: s.normalizedAsHTTPURLString)
    }

    /// Second image URL for fallback loading (original asset).
    var secondOriginalImageURL: URL? {
        guard imageUrls.count > 1 else { return nil }
        return URL(string: imageUrls[1].normalizedAsHTTPURLString)
    }

    /// Price as Double for display (API sends price as string from Prisma Decimal).
    var priceDouble: Double? {
        guard let price else { return nil }
        return Double(price)
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        brand: String? = nil,
        category: String? = nil,
        subcategory: String? = nil,
        price: String? = nil,
        currency: String? = nil,
        imageUrl: String? = nil,
        images: [String]? = nil,
        colors: [String]? = nil,
        sizes: [String]? = nil,
        tags: [String]? = nil,
        gender: String? = nil,
        productType: String? = nil,
        sourceUrl: String? = nil,
        retailer: String? = nil,
        externalId: String? = nil,
        manufacturerCode: String? = nil,
        lastVerifiedAt: String? = nil,
        active: Bool? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.brand = brand
        self.category = category
        self.subcategory = subcategory
        self.price = price
        self.currency = currency
        self.imageUrl = imageUrl
        self.images = images
        self.colors = colors
        self.sizes = sizes
        self.tags = tags
        self.gender = gender
        self.productType = productType
        self.sourceUrl = sourceUrl
        self.retailer = retailer
        self.externalId = externalId
        self.manufacturerCode = manufacturerCode
        self.lastVerifiedAt = lastVerifiedAt
        self.active = active
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        if let s = try container.decodeIfPresent(String.self, forKey: .price) {
            price = s
        } else if let d = try container.decodeIfPresent(Double.self, forKey: .price) {
            price = String(d)
        } else if let i = try container.decodeIfPresent(Int.self, forKey: .price) {
            price = String(i)
        } else {
            price = nil
        }
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        images = try container.decodeIfPresent([String].self, forKey: .images)
        colors = try container.decodeIfPresent([String].self, forKey: .colors)
        sizes = try container.decodeIfPresent([String].self, forKey: .sizes)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        productType = try container.decodeIfPresent(String.self, forKey: .productType)
        sourceUrl = try container.decodeIfPresent(String.self, forKey: .sourceUrl)
        retailer = try container.decodeIfPresent(String.self, forKey: .retailer)
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        manufacturerCode = try container.decodeIfPresent(String.self, forKey: .manufacturerCode)
        lastVerifiedAt = try container.decodeIfPresent(String.self, forKey: .lastVerifiedAt)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Item, rhs: Item) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Image URL Helpers

extension String {
    /// Converts an image path/URL to its background-removed variant.
    /// e.g. "products/brand/sku/0.jpg" -> "products/brand/sku/0-nobg.png"
    var imageUrlNoBg: String {
        if hasSuffix("-nobg.png") { return self }
        return (self as NSString).deletingPathExtension + "-nobg.png"
    }
}

// MARK: - Pagination

struct Pagination: Codable, Sendable {
    let page: Int?
    let limit: Int?
    let total: Int?
    let totalPages: Int?
}

// MARK: - Items Responses

struct PaginatedItemsResponse: Codable, Sendable {
    let items: [Item]
    let pagination: Pagination?
}

struct ItemsFeedResponse: Codable, Sendable {
    let items: [Item]
    let matches: [FeedMatch]?
    let remaining: Int?
}

// MARK: - Feed Match Metadata

/// Why the recommender surfaced a given card. Mirrors `MatchSource` in
/// `feed-personalization.ts` on the backend.
enum FeedMatchSource: String, Codable, Sendable, Hashable {
    case personalized
    case novelty
    case random
    case coldStart = "cold_start"
}

/// Bucketed cluster-similarity grade used to color the badge.
enum FeedMatchBucket: String, Codable, Sendable, Hashable {
    case high
    case medium
    case low
}

/// One of the user's previously-liked items that contributed to the cluster
/// matching the surfaced card. Surfaced in the "because you liked..." UI.
struct MatchContributor: Codable, Sendable, Identifiable, Hashable {
    let itemId: String
    let name: String
    let imageUrl: String?
    let sim: Double

    var id: String { itemId }

    /// Normalized URL for `CachedAsyncImage` (handles relative paths the API may emit).
    var imageURL: URL? {
        guard let s = imageUrl, !s.isEmpty else { return nil }
        return URL(string: s.normalizedAsHTTPURLString)
    }
}

/// Per-card recommendation metadata returned by `/items/feed` alongside each
/// `Item`. Used to render the corner match badge and the tap-to-open
/// explainer sheet.
struct FeedMatch: Codable, Sendable, Hashable, Identifiable {
    let itemId: String
    let source: FeedMatchSource
    let clusterIndex: Int?
    let clusterSim: Double?
    let scorePct: Int?
    let bucket: FeedMatchBucket?
    let topContributors: [MatchContributor]

    var id: String { itemId }

    /// Decode tolerantly: unknown source/bucket strings fall back so a
    /// future backend value can't crash the client.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try c.decode(String.self, forKey: .itemId)
        clusterIndex = try c.decodeIfPresent(Int.self, forKey: .clusterIndex)
        clusterSim = try c.decodeIfPresent(Double.self, forKey: .clusterSim)
        scorePct = try c.decodeIfPresent(Int.self, forKey: .scorePct)
        topContributors = try c.decodeIfPresent([MatchContributor].self, forKey: .topContributors) ?? []
        if let raw = try c.decodeIfPresent(String.self, forKey: .source),
           let parsed = FeedMatchSource(rawValue: raw) {
            source = parsed
        } else {
            source = .random
        }
        if let raw = try c.decodeIfPresent(String.self, forKey: .bucket),
           let parsed = FeedMatchBucket(rawValue: raw) {
            bucket = parsed
        } else {
            bucket = nil
        }
    }

    init(
        itemId: String,
        source: FeedMatchSource,
        clusterIndex: Int? = nil,
        clusterSim: Double? = nil,
        scorePct: Int? = nil,
        bucket: FeedMatchBucket? = nil,
        topContributors: [MatchContributor] = []
    ) {
        self.itemId = itemId
        self.source = source
        self.clusterIndex = clusterIndex
        self.clusterSim = clusterSim
        self.scorePct = scorePct
        self.bucket = bucket
        self.topContributors = topContributors
    }
}

// MARK: - Brands

struct BrandInfo: Codable, Sendable, Identifiable, Hashable {
    let brand: String
    let productCount: Int

    var id: String { brand }
}

struct BrandListResponse: Codable, Sendable {
    let brands: [BrandInfo]
}

struct SetFavoriteBrandRequest: Codable, Sendable {
    let brand: String
    let favorite: Bool
}

struct FavoriteBrandsUpdateResponse: Codable, Sendable {
    let favoriteBrands: [String]
}
