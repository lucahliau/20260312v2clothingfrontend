import Foundation

enum SocialService {
    // MARK: - Search & profile

    static func searchUsers(query: String, limit: Int = 20) async throws -> [UserPreview] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = min(max(limit, 1), APIQueryLimits.maxUserSearch)
        let response: UserSearchResponse = try await NetworkManager.shared.request(
            "/users/search",
            queryItems: [
                URLQueryItem(name: "q", value: trimmed),
                URLQueryItem(name: "limit", value: "\(capped)")
            ]
        )
        return response.items
    }

    static func fetchUserProfile(username: String) async throws -> UserProfile {
        try await NetworkManager.shared.request("/users/\(username)")
    }

    // MARK: - Friend requests

    static func sendFriendRequest(userId: String) async throws -> FriendRequestRow {
        let response: FriendRequestEnvelope = try await NetworkManager.shared.request(
            "/social/friends/request/\(userId)",
            method: "POST"
        )
        return response.friendRequest
    }

    static func cancelFriendRequest(userId: String) async throws -> FriendCancelledResponse {
        try await NetworkManager.shared.request(
            "/social/friends/request/\(userId)",
            method: "DELETE"
        )
    }

    static func acceptFriendRequest(fromUserId: String) async throws -> FriendRequestRow {
        let response: FriendRequestEnvelope = try await NetworkManager.shared.request(
            "/social/friends/requests/\(fromUserId)/accept",
            method: "POST"
        )
        return response.friendRequest
    }

    static func declineFriendRequest(fromUserId: String) async throws -> FriendDeclinedResponse {
        try await NetworkManager.shared.request(
            "/social/friends/requests/\(fromUserId)/decline",
            method: "POST"
        )
    }

    static func removeFriend(userId: String) async throws -> FriendRemovedResponse {
        try await NetworkManager.shared.request(
            "/social/friends/\(userId)",
            method: "DELETE"
        )
    }

    // MARK: - Lists & pending

    static func fetchPending() async throws -> PendingResponse {
        try await NetworkManager.shared.request("/social/pending")
    }

    static func fetchFriends(limit: Int = 50, offset: Int = 0) async throws -> PaginatedUsersResponse {
        try await NetworkManager.shared.request(
            "/social/friends",
            queryItems: paginationQuery(limit: limit, offset: offset)
        )
    }

    /// Items that 2+ of the caller's friends recently liked/loved — feeds the
    /// "your friends found something" local notification.
    static func fetchFriendsHotItems(minFriends: Int = 2, days: Int = 7) async throws -> [FriendsHotItem] {
        let response: FriendsHotItemsResponse = try await NetworkManager.shared.request(
            "/social/friends/hot-items",
            queryItems: [
                URLQueryItem(name: "minFriends", value: "\(minFriends)"),
                URLQueryItem(name: "days", value: "\(days)")
            ]
        )
        return response.items
    }

    // MARK: - Block

    static func blockUser(userId: String) async throws -> BlockResponse {
        try await NetworkManager.shared.request(
            "/social/block/\(userId)",
            method: "POST"
        )
    }

    static func unblockUser(userId: String) async throws -> UnblockResponse {
        try await NetworkManager.shared.request(
            "/social/block/\(userId)",
            method: "DELETE"
        )
    }

    // MARK: - Report

    static func reportUser(userId: String, reason: String, details: String? = nil) async throws -> ReportResponse {
        try await NetworkManager.shared.request(
            "/social/report/\(userId)",
            method: "POST",
            body: ReportUserRequest(reason: reason, details: details)
        )
    }

    private static func paginationQuery(limit: Int, offset: Int) -> [URLQueryItem] {
        let l = min(max(limit, 1), 100)
        let o = max(offset, 0)
        return [
            URLQueryItem(name: "limit", value: "\(l)"),
            URLQueryItem(name: "offset", value: "\(o)")
        ]
    }
}
