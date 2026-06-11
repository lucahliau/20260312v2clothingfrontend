import Foundation

enum MessagingService {
    // MARK: - Conversations

    static func fetchConversations(limit: Int = 50, offset: Int = 0) async throws -> [ConversationThread] {
        let l = min(max(limit, 1), APIQueryLimits.maxConversationsPage)
        let o = max(offset, 0)
        let response: ConversationsListResponse = try await NetworkManager.shared.request(
            "/messages/conversations",
            queryItems: [
                URLQueryItem(name: "limit", value: "\(l)"),
                URLQueryItem(name: "offset", value: "\(o)")
            ]
        )
        return response.conversations
    }

    static func openOrCreateConversation(userId: String) async throws -> ConversationThread {
        let body = OpenConversationRequest(userId: userId)
        let response: OpenConversationResponse = try await NetworkManager.shared.request(
            "/messages/conversations",
            method: "POST",
            body: body
        )
        return response.conversation
    }

    static func fetchConversation(conversationId: String) async throws -> ConversationDetail {
        let response: ConversationDetailResponse = try await NetworkManager.shared.request(
            "/messages/conversations/\(conversationId)"
        )
        return response.conversation
    }

    // MARK: - Messages

    static func fetchMessages(
        conversationId: String,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> MessagesPageResponse {
        let l = min(max(limit, 1), APIQueryLimits.maxMessagesPage)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(l)")
        ]
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return try await NetworkManager.shared.request(
            "/messages/conversations/\(conversationId)/messages",
            queryItems: items
        )
    }

    static func sendMessage(
        conversationId: String,
        content: String?,
        itemId: String?
    ) async throws -> ConversationMessage {
        let trimmed = content?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (trimmed?.isEmpty == false) ? trimmed : nil
        guard text != nil || (itemId != nil && !(itemId!.isEmpty)) else {
            throw NetworkError.serverError(statusCode: 400, message: "Message must include text or a product.", code: nil)
        }
        let body = SendMessageRequest(content: text, itemId: itemId)
        let response: SendMessageAPIResponse = try await NetworkManager.shared.request(
            "/messages/conversations/\(conversationId)/messages",
            method: "POST",
            body: body
        )
        return response.message
    }

    static func markRead(conversationId: String) async throws {
        try await NetworkManager.shared.requestVoid(
            "/messages/conversations/\(conversationId)/read",
            method: "PATCH"
        )
    }

    static func deleteMessage(messageId: String) async throws {
        try await NetworkManager.shared.requestVoid(
            "/messages/messages/\(messageId)",
            method: "DELETE"
        )
    }
}
