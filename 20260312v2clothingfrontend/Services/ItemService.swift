import Foundation

enum ItemService {
    /// Lists clothing items with optional filters and pagination.
    /// Query params: page, limit, category, brand, etc.
    static func fetchItems(
        page: Int? = nil,
        limit: Int? = nil,
        category: String? = nil,
        brand: String? = nil
    ) async throws -> [Item] {
        var queryItems: [URLQueryItem] = []
        if let page { queryItems.append(URLQueryItem(name: "page", value: "\(page)")) }
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: "\(limit)")) }
        if let category, !category.isEmpty { queryItems.append(URLQueryItem(name: "category", value: category)) }
        if let brand, !brand.isEmpty { queryItems.append(URLQueryItem(name: "brand", value: brand)) }

        let response: PaginatedItemsResponse = try await NetworkManager.shared.request(
            "/items",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        return response.items
    }

    /// Returns a feed of items not yet swiped by the user.
    static func fetchFeedItems() async throws -> [Item] {
        let response: ItemsFeedResponse = try await NetworkManager.shared.request("/items/feed")
        return response.items
    }

    /// Returns a single clothing item by ID.
    static func fetchItem(id: String) async throws -> Item {
        try await NetworkManager.shared.request("/items/\(id)")
    }
}
