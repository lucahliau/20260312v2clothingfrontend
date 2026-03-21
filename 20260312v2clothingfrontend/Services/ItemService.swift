import Foundation

enum ItemService {
    /// Fetches a single page of items with full pagination metadata.
    static func fetchItemsPage(
        page: Int = 1,
        limit: Int = 100,
        category: String? = nil,
        brand: String? = nil,
        search: String? = nil,
        gender: String? = nil,
        productType: String? = nil
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

    /// Fetches all items by paginating through every page.
    static func fetchAllItems() async throws -> [Item] {
        var all: [Item] = []
        var page = 1
        let limit = 100
        while true {
            let response = try await fetchItemsPage(page: page, limit: limit)
            all += response.items
            guard let pag = response.pagination,
                  let totalPages = pag.totalPages,
                  page < totalPages else { break }
            page += 1
        }
        return all
    }

    /// Returns a feed of items not yet swiped by the user.
    static func fetchFeedItems(
        limit: Int = 20,
        category: String? = nil,
        genders: [String]? = nil,
        productTypes: [String]? = nil
    ) async throws -> [Item] {
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
            queryItems: queryItems
        )
        return response.items
    }

    /// Returns a single clothing item by ID.
    static func fetchItem(id: String) async throws -> Item {
        try await NetworkManager.shared.request("/items/\(id)")
    }
}
