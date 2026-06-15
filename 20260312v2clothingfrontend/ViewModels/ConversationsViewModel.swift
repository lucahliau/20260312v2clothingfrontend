import Foundation
import Observation

@Observable
@MainActor
final class ConversationsViewModel {
    var conversations: [ConversationThread] = []
    var isLoading = false
    var errorMessage: String?

    private var didLoadOnce = false

    func loadIfNeeded() async {
        guard !didLoadOnce else { return }
        didLoadOnce = true
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            conversations = try await MessagingService.fetchConversations(limit: 50, offset: 0)
        } catch {
            errorMessage = error.localizedDescription
            conversations = []
        }
    }

    func applyUpdatedThread(_ thread: ConversationThread) {
        if let idx = conversations.firstIndex(where: { $0.id == thread.id }) {
            conversations[idx] = thread
        } else {
            conversations.insert(thread, at: 0)
        }
        sortThreads()
    }

    func sortThreads() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }
}
