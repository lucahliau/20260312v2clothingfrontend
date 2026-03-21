import Foundation

enum SwipeType: String, Codable, Sendable {
    case LOVE
    case LIKE
    case DISLIKE
    case NEUTRAL
}

struct SwipeRequest: Codable, Sendable {
    let itemId: String
    let action: SwipeType
}

struct UpdateSwipeRequest: Codable, Sendable {
    let action: SwipeType
}

struct SwipeRecord: Codable, Sendable, Identifiable {
    let id: String
    let userId: String?
    let itemId: String
    let action: SwipeType
    let item: Item?
    let createdAt: String?
}

struct PaginatedSwipesResponse: Codable, Sendable {
    let swipes: [SwipeRecord]
    let pagination: Pagination?
}
