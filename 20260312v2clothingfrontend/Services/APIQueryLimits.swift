import Foundation

/// Backend caps for `limit` query parameters (`GET /brands`, `GET /brands/explore`, `GET /items`).
enum APIQueryLimits {
    static let maxBrands = 500_000
    static let maxExploreBrands = 100_000
    static let maxItemsPerPage = 500_000
    /// `GET /users/search` — backend max 30.
    static let maxUserSearch = 30
    /// `GET /messages/conversations` and `GET .../messages` — backend max 100.
    static let maxMessagesPage = 100
    /// `GET /messages/conversations` list — backend max 100.
    static let maxConversationsPage = 100
}
