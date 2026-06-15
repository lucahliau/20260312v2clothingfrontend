import Foundation

// MARK: - Conversation (list + open)

/// Inner `conversation` object from the API (id + timestamps only; `otherUser` is a sibling field).
private struct ConversationMeta: Decodable, Sendable {
    let id: String
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
    }

    /// Prefer `updatedAt` for sorting/display; fall back to `createdAt`.
    var sortTimestamp: String {
        if let u = updatedAt?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty { return u }
        if let c = createdAt?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        return ""
    }
}

/// A DM thread row for UI: built from `GET /messages/conversations` items or `POST /messages/conversations`.
struct ConversationThread: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let updatedAt: String
    let otherUser: UserPreview
    let lastMessage: MessagePreview?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt
        case otherUser
        case lastMessage
        case unreadCount
    }

    init(
        id: String,
        updatedAt: String,
        otherUser: UserPreview,
        lastMessage: MessagePreview?,
        unreadCount: Int
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.otherUser = otherUser
        self.lastMessage = lastMessage
        self.unreadCount = unreadCount
    }

    /// Legacy flat thread JSON (rare); prefer wrapper decoding via `ConversationsListResponse` / `OpenConversationResponse`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        otherUser = try c.decode(UserPreview.self, forKey: .otherUser)
        lastMessage = try c.decodeIfPresent(MessagePreview.self, forKey: .lastMessage)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(otherUser, forKey: .otherUser)
        try c.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try c.encode(unreadCount, forKey: .unreadCount)
    }
}

/// `GET /messages/conversations` → `{ total, items[] }` where each item wraps `conversation` + `otherUser` + metadata.
struct ConversationsListResponse: Decodable, Sendable {
    let conversations: [ConversationThread]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case total
        case items
        case conversations
    }

    private struct ConversationListRow: Decodable, Sendable {
        let conversation: ConversationMeta
        let otherUser: UserPreview
        let lastMessage: MessagePreview?
        let unreadCount: Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent(Int.self, forKey: .total)

        if let rows = try c.decodeIfPresent([ConversationListRow].self, forKey: .items) {
            conversations = rows.map { row in
                ConversationThread(
                    id: row.conversation.id,
                    updatedAt: row.conversation.sortTimestamp,
                    otherUser: row.otherUser,
                    lastMessage: row.lastMessage,
                    unreadCount: row.unreadCount
                )
            }
            return
        }

        if let list = try c.decodeIfPresent([ConversationThread].self, forKey: .conversations) {
            conversations = list
            return
        }

        conversations = []
    }
}

/// Last message snippet on a thread row.
struct MessagePreview: Codable, Sendable, Hashable {
    let id: String?
    let content: String?
    let itemId: String?
    let createdAt: String?
    /// Optional human-readable preview when content is empty (e.g. product shared).
    let preview: String?

    var displayText: String {
        if let p = preview?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty { return p }
        if let c = content?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { return c }
        if itemId != nil { return "Shared a product" }
        return ""
    }
}

// MARK: - Open conversation

struct OpenConversationRequest: Encodable, Sendable {
    let userId: String
}

/// `POST /messages/conversations` → `{ conversation, otherUser }` (201/200).
struct OpenConversationResponse: Decodable, Sendable {
    let conversation: ConversationThread

    private enum CodingKeys: String, CodingKey {
        case conversation
        case otherUser
        case data
        case thread
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let meta = try c.decodeIfPresent(ConversationMeta.self, forKey: .conversation),
           let other = try c.decodeIfPresent(UserPreview.self, forKey: .otherUser) {
            conversation = ConversationThread(
                id: meta.id,
                updatedAt: meta.sortTimestamp,
                otherUser: other,
                lastMessage: nil,
                unreadCount: 0
            )
            return
        }

        if let conv = try? c.decode(ConversationThread.self, forKey: .conversation) {
            conversation = conv
            return
        }
        if let conv = try? c.decode(ConversationThread.self, forKey: .data) {
            conversation = conv
            return
        }
        if let conv = try? c.decode(ConversationThread.self, forKey: .thread) {
            conversation = conv
            return
        }

        conversation = try ConversationThread(from: decoder)
    }
}

// MARK: - Conversation detail (GET single)

/// `GET /messages/conversations/:id` → `{ conversation, participants, otherUser, unreadCount }`.
struct ConversationDetailResponse: Decodable, Sendable {
    let conversation: ConversationDetail

    private enum CodingKeys: String, CodingKey {
        case conversation
        case participants
        case otherUser
        case unreadCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        if let meta = try c.decodeIfPresent(ConversationMeta.self, forKey: .conversation),
           let other = try c.decodeIfPresent(UserPreview.self, forKey: .otherUser) {
            let unread = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
            let participants = try c.decodeIfPresent([ConversationParticipant].self, forKey: .participants)
            conversation = ConversationDetail(
                id: meta.id,
                updatedAt: meta.updatedAt ?? meta.createdAt,
                otherUser: other,
                unreadCount: unread,
                participants: participants
            )
            return
        }

        if let detail = try c.decodeIfPresent(ConversationDetail.self, forKey: .conversation) {
            conversation = detail
            return
        }

        conversation = try ConversationDetail(from: decoder)
    }
}

struct ConversationDetail: Codable, Sendable, Identifiable {
    let id: String
    let updatedAt: String?
    let otherUser: UserPreview
    let unreadCount: Int
    let participants: [ConversationParticipant]?

    init(
        id: String,
        updatedAt: String?,
        otherUser: UserPreview,
        unreadCount: Int,
        participants: [ConversationParticipant]?
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.otherUser = otherUser
        self.unreadCount = unreadCount
        self.participants = participants
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        otherUser = try c.decode(UserPreview.self, forKey: .otherUser)
        unreadCount = try c.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        participants = try c.decodeIfPresent([ConversationParticipant].self, forKey: .participants)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case updatedAt
        case otherUser
        case unreadCount
        case participants
    }
}

/// Backend may send `{ userId, lastReadAt }` or `{ user: UserPreview, lastReadAt }`.
struct ConversationParticipant: Codable, Sendable, Hashable {
    let userId: String
    let lastReadAt: String?

    enum CodingKeys: String, CodingKey {
        case userId
        case user
        case lastReadAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uid = try c.decodeIfPresent(String.self, forKey: .userId), !uid.isEmpty {
            userId = uid
        } else if let u = try c.decodeIfPresent(UserPreview.self, forKey: .user) {
            userId = u.id
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.userId,
                .init(codingPath: c.codingPath, debugDescription: "Expected userId or user")
            )
        }
        lastReadAt = try c.decodeIfPresent(String.self, forKey: .lastReadAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        try c.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
    }
}

// MARK: - Messages

struct ConversationMessage: Decodable, Sendable, Identifiable {
    let id: String
    let conversationId: String?
    let senderId: String
    let content: String?
    let itemId: String?
    let item: Item?
    let createdAt: String
    let deletedAt: String?
    /// Backend uses `deleted: true` on deleted messages (no `deletedAt`).
    private let deletedFlag: Bool?

    var isDeleted: Bool {
        deletedFlag == true || deletedAt != nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case conversationId
        case conversation_id
        case senderId
        case sender_id
        case content
        case itemId
        case item_id
        case item
        case createdAt
        case created_at
        case deletedAt
        case deleted_at
        case deleted
        case isOwn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversationId = try Self.decodeOptionalString(c, primary: .conversationId, alternate: .conversation_id)
        senderId = try Self.decodeRequiredString(c, primary: .senderId, alternate: .sender_id)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        itemId = try Self.decodeOptionalString(c, primary: .itemId, alternate: .item_id)
        if c.contains(.item) {
            item = try? c.decode(Item.self, forKey: .item)
        } else {
            item = nil
        }
        createdAt = try Self.decodeRequiredString(c, primary: .createdAt, alternate: .created_at)
        deletedAt = try Self.decodeOptionalString(c, primary: .deletedAt, alternate: .deleted_at)
        deletedFlag = try c.decodeIfPresent(Bool.self, forKey: .deleted)
        _ = try c.decodeIfPresent(Bool.self, forKey: .isOwn)
    }

    private static func decodeRequiredString(
        _ c: KeyedDecodingContainer<CodingKeys>,
        primary: CodingKeys,
        alternate: CodingKeys
    ) throws -> String {
        if let s = try c.decodeIfPresent(String.self, forKey: primary), !s.isEmpty { return s }
        if let s = try c.decodeIfPresent(String.self, forKey: alternate), !s.isEmpty { return s }
        throw DecodingError.keyNotFound(
            primary,
            .init(codingPath: c.codingPath, debugDescription: "Missing required string (tried \(primary) and \(alternate))")
        )
    }

    private static func decodeOptionalString(
        _ c: KeyedDecodingContainer<CodingKeys>,
        primary: CodingKeys,
        alternate: CodingKeys
    ) throws -> String? {
        if let s = try c.decodeIfPresent(String.self, forKey: primary), !s.isEmpty { return s }
        if let s = try c.decodeIfPresent(String.self, forKey: alternate), !s.isEmpty { return s }
        return nil
    }
}

struct MessagesPageResponse: Decodable, Sendable {
    let messages: [ConversationMessage]
    let nextCursor: String?
    let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case messages
        case items
        case nextCursor
        case next_cursor
        case cursor
        case hasMore
        case has_more
        case data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.data) {
            let inner = try c.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
            messages = try Self.decodeMessageList(from: inner)
            nextCursor = try Self.decodeCursor(from: inner)
            hasMore = try Self.decodeHasMore(from: inner)
        } else {
            messages = try Self.decodeMessageList(from: c)
            nextCursor = try Self.decodeCursor(from: c)
            hasMore = try Self.decodeHasMore(from: c)
        }
    }

    private static func decodeMessageList(from c: KeyedDecodingContainer<CodingKeys>) throws -> [ConversationMessage] {
        if let m = try c.decodeIfPresent([ConversationMessage].self, forKey: .messages) { return m }
        if let m = try c.decodeIfPresent([ConversationMessage].self, forKey: .items) { return m }
        return []
    }

    private static func decodeCursor(from c: KeyedDecodingContainer<CodingKeys>) throws -> String? {
        if let s = try c.decodeIfPresent(String.self, forKey: .nextCursor), !s.isEmpty { return s }
        if let s = try c.decodeIfPresent(String.self, forKey: .next_cursor), !s.isEmpty { return s }
        if let s = try c.decodeIfPresent(String.self, forKey: .cursor), !s.isEmpty { return s }
        return nil
    }

    private static func decodeHasMore(from c: KeyedDecodingContainer<CodingKeys>) throws -> Bool {
        if let b = try c.decodeIfPresent(Bool.self, forKey: .hasMore) { return b }
        if let b = try c.decodeIfPresent(Bool.self, forKey: .has_more) { return b }
        return false
    }
}

struct SendMessageRequest: Encodable, Sendable {
    var content: String?
    var itemId: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(itemId, forKey: .itemId)
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case itemId
    }
}

struct DeleteMessageResponse: Codable, Sendable {
    let deleted: Bool?
    let success: Bool?
}

// MARK: - Send message response

/// `POST .../messages` → `{ message: <serialized> }` (201).
struct SendMessageAPIResponse: Decodable, Sendable {
    let message: ConversationMessage

    private enum CodingKeys: String, CodingKey {
        case message
        case data
    }

    private enum DataInnerKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let m = try c.decodeIfPresent(ConversationMessage.self, forKey: .message) {
            message = m
            return
        }
        if let m = try? c.decode(ConversationMessage.self, forKey: .data) {
            message = m
            return
        }
        if let inner = try? c.nestedContainer(keyedBy: DataInnerKeys.self, forKey: .data),
           let m = try? inner.decode(ConversationMessage.self, forKey: .message) {
            message = m
            return
        }
        message = try ConversationMessage(from: decoder)
    }
}
