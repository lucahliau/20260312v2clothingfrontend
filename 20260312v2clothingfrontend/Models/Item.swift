import Foundation

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
