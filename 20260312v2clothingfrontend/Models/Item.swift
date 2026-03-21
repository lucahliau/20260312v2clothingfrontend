import Foundation

// MARK: - Filter Enums

enum ProductType: String, CaseIterable, Sendable {
    case tops, bottoms, bags, accessories, jackets, other
    var displayName: String { rawValue.capitalized }
}

enum GenderFilter: String, CaseIterable, Sendable {
    case male, female, unisex
    var displayName: String { rawValue.capitalized }
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
            return raw.map { (primary: $0.imageUrlNoBg, fallback: $0) }
        }
        return raw.map { (primary: $0, fallback: nil) }
    }

    /// Set to `true` to use background-removed (-nobg.png) variants, falling back to original if nobg missing.
    static var useBackgroundRemovedImages = true

    /// First catalog image URL (original asset, not `-nobg`). Use for explore collages and brand grids when full product photos are preferred.
    var firstOriginalImageURL: URL? {
        guard let s = imageUrls.first else { return nil }
        return URL(string: s)
    }

    /// Second image URL for fallback loading (original asset).
    var secondOriginalImageURL: URL? {
        guard imageUrls.count > 1 else { return nil }
        return URL(string: imageUrls[1])
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
        price = try container.decodeIfPresent(String.self, forKey: .price)
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
    let remaining: Int?
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
