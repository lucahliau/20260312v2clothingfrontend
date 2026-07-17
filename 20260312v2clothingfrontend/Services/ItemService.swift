import Foundation

private nonisolated struct FeedContinuationRequest: Codable, Sendable {
    let excludeIds: [String]
}

enum ItemService {
    /// Fetches a single page of items with full pagination metadata.
    static func fetchItemsPage(
        page: Int = 1,
        limit: Int = 100,
        category: String? = nil,
        brand: String? = nil,
        search: String? = nil,
        gender: String? = nil,
        productType: String? = nil,
        minPrice: Double? = nil,
        maxPrice: Double? = nil
    ) async throws -> PaginatedItemsResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let category, !category.isEmpty { queryItems.append(URLQueryItem(name: "category", value: category)) }
        if let brand, !brand.isEmpty { queryItems.append(URLQueryItem(name: "brand", value: brand)) }
        if let search, !search.isEmpty { queryItems.append(URLQueryItem(name: "search", value: search)) }
        if let gender, !gender.isEmpty { queryItems.append(URLQueryItem(name: "gender", value: gender)) }
        if let productType, !productType.isEmpty { queryItems.append(URLQueryItem(name: "productType", value: productType)) }
        if let minPrice { queryItems.append(URLQueryItem(name: "minPrice", value: "\(Int(minPrice))")) }
        if let maxPrice { queryItems.append(URLQueryItem(name: "maxPrice", value: "\(Int(maxPrice))")) }

        return try await NetworkManager.shared.request(
            "/items",
            queryItems: queryItems
        )
    }

    /// Lists clothing items with optional filters and pagination.
    /// Query params: page, limit, category, brand, etc.
    static func fetchItems(
        page: Int? = nil,
        limit: Int? = nil,
        category: String? = nil,
        brand: String? = nil,
        search: String? = nil
    ) async throws -> [Item] {
        let response = try await fetchItemsPage(
            page: page ?? 1,
            limit: limit ?? 100,
            category: category,
            brand: brand,
            search: search
        )
        return response.items
    }

    /// Fetches every matching item by paginating until all pages are loaded (`limit` per request matches API max).
    static func fetchAllItemsPages(
        category: String? = nil,
        brand: String? = nil,
        search: String? = nil,
        gender: String? = nil,
        productType: String? = nil
    ) async throws -> [Item] {
        var all: [Item] = []
        var page = 1
        let limit = APIQueryLimits.maxItemsPerPage
        while true {
            let response = try await fetchItemsPage(
                page: page,
                limit: limit,
                category: category,
                brand: brand,
                search: search,
                gender: gender,
                productType: productType
            )
            if response.items.isEmpty { break }
            all += response.items
            guard let pag = response.pagination,
                  let totalPages = pag.totalPages,
                  page < totalPages else { break }
            page += 1
        }
        return all
    }

    /// Fetches all items by paginating through every page.
    static func fetchAllItems() async throws -> [Item] {
        try await fetchAllItemsPages()
    }

    /// Returns a feed of items not yet swiped by the user.
    static func fetchFeedItems(
        limit: Int = 20,
        category: String? = nil,
        genders: [String]? = nil,
        productTypes: [String]? = nil
    ) async throws -> [Item] {
        try await fetchFeedItemsWithMatches(
            limit: limit,
            category: category,
            genders: genders,
            productTypes: productTypes
        ).items
    }

    /// Returns a feed of items plus per-card recommendation metadata so the
    /// client can render match-likelihood badges. Older callers can keep
    /// using `fetchFeedItems` and ignore matches.
    static func fetchFeedItemsWithMatches(
        limit: Int = 20,
        category: String? = nil,
        genders: [String]? = nil,
        productTypes: [String]? = nil,
        excludingIds: [String] = []
    ) async throws -> (items: [Item], matches: [FeedMatch], hasMore: Bool) {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
        if let category, !category.isEmpty { queryItems.append(URLQueryItem(name: "category", value: category)) }
        for g in genders ?? [] where !g.isEmpty {
            queryItems.append(URLQueryItem(name: "gender", value: g))
        }
        for p in productTypes ?? [] where !p.isEmpty {
            queryItems.append(URLQueryItem(name: "productType", value: p))
        }

        let response: ItemsFeedResponse = try await NetworkManager.shared.request(
            "/items/feed",
            method: excludingIds.isEmpty ? "GET" : "POST",
            body: excludingIds.isEmpty ? nil : FeedContinuationRequest(excludeIds: excludingIds),
            queryItems: queryItems
        )
        return (response.items, response.matches ?? [], response.hasMore ?? !response.items.isEmpty)
    }

    /// Returns a single clothing item by ID.
    static func fetchItem(id: String) async throws -> Item {
        try await NetworkManager.shared.request("/items/\(id)")
    }

    /// Visually similar items (CLIP image-embedding nearest neighbours) for the
    /// "More like this" rail. The server falls back to same-brand recents when
    /// the item has no embedding, so this rarely returns empty. Reuses
    /// `PaginatedItemsResponse` — the endpoint omits `pagination`, which decodes
    /// to `nil`.
    static func fetchSimilarItems(id: String, limit: Int = 12) async throws -> [Item] {
        let response: PaginatedItemsResponse = try await NetworkManager.shared.request(
            "/items/\(id)/similar",
            queryItems: [URLQueryItem(name: "limit", value: "\(limit)")]
        )
        return response.items
    }
}
