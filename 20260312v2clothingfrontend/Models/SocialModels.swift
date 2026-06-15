import Foundation

// MARK: - Search & preview

struct UserPreview: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let username: String
    let firstName: String?
    let lastName: String?
    let avatarUrl: String?
    let profileIsPrivate: Bool?
}

struct UserSearchResponse: Codable, Sendable {
    let items: [UserPreview]
}

// MARK: - Profile & relationship

struct UserRelationship: Codable, Sendable, Hashable {
    let friendship: String
}

struct UserProfile: Codable, Sendable, Identifiable {
    let id: String
    let username: String
    var firstName: String?
    var lastName: String?
    var avatarUrl: String?
    var bio: String?
    var profileIsPrivate: Bool?
    var onboardingCompleted: Bool?
    var friendsCount: Int?
    var relationship: UserRelationship?
    /// Present on full profile when viewer can see full fields.
    var location: String?
    var gender: String?
    var stylePreferences: [String]?
    var favoriteBrands: [String]?
    var createdAt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        firstName = try c.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try c.decodeIfPresent(String.self, forKey: .lastName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        bio = try c.decodeIfPresent(String.self, forKey: .bio)
        profileIsPrivate = try c.decodeIfPresent(Bool.self, forKey: .profileIsPrivate)
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
        friendsCount = try c.decodeIfPresent(Int.self, forKey: .friendsCount)
            ?? c.decodeIfPresent(Int.self, forKey: .friends_count)
        relationship = try c.decodeIfPresent(UserRelationship.self, forKey: .relationship)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        stylePreferences = try c.decodeIfPresent([String].self, forKey: .stylePreferences)
        favoriteBrands = try c.decodeIfPresent([String].self, forKey: .favoriteBrands)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, firstName, lastName, avatarUrl, bio, profileIsPrivate, onboardingCompleted
        case friendsCount, friends_count
        case relationship, location, gender, stylePreferences, favoriteBrands, createdAt
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(username, forKey: .username)
        try c.encodeIfPresent(firstName, forKey: .firstName)
        try c.encodeIfPresent(lastName, forKey: .lastName)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try c.encodeIfPresent(bio, forKey: .bio)
        try c.encodeIfPresent(profileIsPrivate, forKey: .profileIsPrivate)
        try c.encodeIfPresent(onboardingCompleted, forKey: .onboardingCompleted)
        try c.encodeIfPresent(friendsCount, forKey: .friendsCount)
        try c.encodeIfPresent(relationship, forKey: .relationship)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(stylePreferences, forKey: .stylePreferences)
        try c.encodeIfPresent(favoriteBrands, forKey: .favoriteBrands)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
    }
}

// MARK: - Friend requests

struct FriendRequestRow: Codable, Sendable, Hashable {
    let id: String
    let fromUserId: String
    let toUserId: String
    let status: String
    let createdAt: String
    let updatedAt: String?
}

struct FriendRequestEnvelope: Codable, Sendable {
    let friendRequest: FriendRequestRow
}

struct FriendRequestBrief: Codable, Sendable, Hashable {
    let id: String
    let createdAt: String
}

struct IncomingFriendRequestItem: Codable, Sendable, Identifiable {
    var id: String { friendRequest.id }
    let friendRequest: FriendRequestBrief
    let user: UserPreview
}

struct OutgoingFriendRequestItem: Codable, Sendable, Identifiable {
    var id: String { friendRequest.id }
    let friendRequest: FriendRequestBrief
    let user: UserPreview
}

struct FriendDeclinedResponse: Codable, Sendable {
    let declined: Bool
}

struct FriendRemovedResponse: Codable, Sendable {
    let removed: Bool
}

struct FriendCancelledResponse: Codable, Sendable {
    let cancelled: Bool
}

// MARK: - Pending inbox

struct PendingResponse: Codable, Sendable {
    var incomingFriendRequests: [IncomingFriendRequestItem]
    var outgoingFriendRequests: [OutgoingFriendRequestItem]

    init(
        incomingFriendRequests: [IncomingFriendRequestItem] = [],
        outgoingFriendRequests: [OutgoingFriendRequestItem] = []
    ) {
        self.incomingFriendRequests = incomingFriendRequests
        self.outgoingFriendRequests = outgoingFriendRequests
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        incomingFriendRequests = try c.decodeIfPresent([IncomingFriendRequestItem].self, forKey: .incomingFriendRequests) ?? []
        outgoingFriendRequests = try c.decodeIfPresent([OutgoingFriendRequestItem].self, forKey: .outgoingFriendRequests) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case incomingFriendRequests, outgoingFriendRequests
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(incomingFriendRequests, forKey: .incomingFriendRequests)
        try c.encode(outgoingFriendRequests, forKey: .outgoingFriendRequests)
    }
}

// MARK: - Paginated lists

struct PaginatedUsersResponse: Codable, Sendable {
    let total: Int
    let items: [UserPreview]
}

// MARK: - Friends hot items

/// An item that several friends recently liked (from `/social/friends/hot-items`).
struct FriendsHotItem: Codable, Sendable, Identifiable {
    let item: Item
    let friendCount: Int

    var id: String { item.id }
}

struct FriendsHotItemsResponse: Codable, Sendable {
    let items: [FriendsHotItem]
}

// MARK: - Block

struct BlockResponse: Codable, Sendable {
    let blocked: Bool
}

struct UnblockResponse: Codable, Sendable {
    let unblocked: Bool
}

// MARK: - Report

struct ReportUserRequest: Codable, Sendable {
    let reason: String
    let details: String?
}

struct ReportResponse: Codable, Sendable {
    let reported: Bool
    let reportId: String
}
