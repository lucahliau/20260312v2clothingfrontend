import Foundation
import Observation

@Observable
@MainActor
final class ConversationViewModel {
    /// Set when opening from inbox; otherwise opened via friend row.
    var conversationId: String?
    let otherUser: UserPreview

    var messages: [ConversationMessage] = []
    var nextCursor: String?
    var hasMore = false
    var isLoadingInitial = false
    var isLoadingOlder = false
    var isSending = false
    var errorMessage: String?

    var currentUserId: String?

    private var didLoadThread = false
    /// Deduplicates concurrent `openOrCreateConversation` calls (e.g. load + send).
    private var inflightOpenConversation: Task<String, Error>?

    init(conversationId: String?, otherUser: UserPreview) {
        self.conversationId = conversationId
        self.otherUser = otherUser
    }

    var canSend: Bool {
        !isSending
    }

    /// Composer can send when not busy; `sendText` / `sendProduct` always `ensureConversationId()` so we never drop silently.
    var canSendMessage: Bool {
        !isSending
    }

    func isFromMe(_ message: ConversationMessage) -> Bool {
        guard let uid = currentUserId else { return false }
        return message.senderId == uid
    }

    func loadThreadIfNeeded() async {
        guard !didLoadThread else { return }
        await loadInitial()
    }

    /// Call after a failed `loadInitial` (e.g. user taps Retry).
    func retryLoadThread() async {
        await loadInitial()
    }

    func loadInitial() async {
        isLoadingInitial = true
        errorMessage = nil
        defer { isLoadingInitial = false }

        do {
            if currentUserId == nil {
                let me = try await UserService.fetchCurrentUser()
                currentUserId = me.id
            }

            let cid = try await ensureConversationId()

            try await MessagingService.markRead(conversationId: cid)

            let page = try await MessagingService.fetchMessages(conversationId: cid, cursor: nil, limit: 30)
            messages = Array(page.messages.reversed())
            nextCursor = page.nextCursor
            hasMore = page.hasMore

            didLoadThread = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadOlder() async {
        guard let cid = conversationId, let cursor = nextCursor, hasMore, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await MessagingService.fetchMessages(conversationId: cid, cursor: cursor, limit: 30)
            let olderBatch = Array(page.messages.reversed())
            let existing = Set(messages.map(\.id))
            let newOlder = olderBatch.filter { !existing.contains($0.id) }
            messages = newOlder + messages
            nextCursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// - Returns: `true` if the message was sent and applied to the thread.
    @discardableResult
    func sendText(_ raw: String) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            if currentUserId == nil {
                let me = try await UserService.fetchCurrentUser()
                currentUserId = me.id
            }
            let cid = try await ensureConversationId()
            let sent = try await MessagingService.sendMessage(conversationId: cid, content: text, itemId: nil)
            upsertMessage(sent)
            try await MessagingService.markRead(conversationId: cid)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// - Returns: `true` if the product message was sent and applied to the thread.
    @discardableResult
    func sendProduct(itemId: String) async -> Bool {
        guard !itemId.isEmpty else { return false }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            if currentUserId == nil {
                let me = try await UserService.fetchCurrentUser()
                currentUserId = me.id
            }
            let cid = try await ensureConversationId()
            let sent = try await MessagingService.sendMessage(conversationId: cid, content: nil, itemId: itemId)
            upsertMessage(sent)
            try await MessagingService.markRead(conversationId: cid)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteMessage(id: String) async {
        errorMessage = nil
        do {
            try await MessagingService.deleteMessage(messageId: id)
            messages.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    /// Ensures `conversationId` is set, coalescing concurrent opens into one request.
    private func ensureConversationId() async throws -> String {
        if let cid = conversationId, !cid.isEmpty {
            return cid
        }
        if let existing = inflightOpenConversation {
            let id = try await existing.value
            return id
        }
        let task = Task<String, Error> {
            let thread = try await MessagingService.openOrCreateConversation(userId: otherUser.id)
            await MainActor.run {
                self.conversationId = thread.id
            }
            return thread.id
        }
        inflightOpenConversation = task
        defer { inflightOpenConversation = nil }
        return try await task.value
    }

    private func upsertMessage(_ message: ConversationMessage) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        } else {
            messages.append(message)
            messages.sort { $0.createdAt < $1.createdAt }
        }
    }
}
