import Foundation

enum SwipeService {
    /// Records a swipe (like, pass, or superlike) on an item.
    static func recordSwipe(itemId: String, type: SwipeType) async throws {
        let body = SwipeRequest(itemId: itemId, action: type)
        try await NetworkManager.shared.requestVoid(
            "/swipes",
            method: "POST",
            body: body
        )
    }

    /// Returns paginated swipe history for the user.
    static func fetchSwipeHistory(page: Int? = nil, limit: Int? = nil) async throws -> [SwipeRecord] {
        var queryItems: [URLQueryItem] = []
        if let page { queryItems.append(URLQueryItem(name: "page", value: "\(page)")) }
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: "\(limit)")) }

        let response: PaginatedSwipesResponse = try await NetworkManager.shared.request(
            "/swipes/history",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        return response.swipes
    }

    /// Undoes the most recent swipe.
    static func undoLastSwipe() async throws {
        try await NetworkManager.shared.requestVoid(
            "/swipes/last",
            method: "DELETE"
        )
    }
}
