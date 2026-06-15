import Foundation
import Observation

@Observable
@MainActor
final class FriendsViewModel {
    var searchText = ""
    var searchResults: [UserPreview] = []
    var isSearching = false

    var pendingData: PendingResponse?
    var isLoadingPending = false

    var friends: [UserPreview] = []
    var isLoadingFriends = false

    var errorMessage: String?

    private var searchDebounceTask: Task<Void, Never>?
    private var searchGeneration = 0

    private var didLoadInitial = false

    var pendingBadgeCount: Int {
        pendingData?.incomingFriendRequests.count ?? 0
    }

    func loadIfNeeded() async {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        await loadPending()
        await loadFriends()
    }

    func refreshAll() async {
        await loadPending()
        await loadFriends()
    }

    func loadPending() async {
        isLoadingPending = true
        errorMessage = nil
        defer { isLoadingPending = false }
        do {
            pendingData = try await SocialService.fetchPending()
        } catch {
            errorMessage = error.localizedDescription
            if pendingData == nil {
                pendingData = PendingResponse()
            }
        }
    }

    func loadFriends() async {
        isLoadingFriends = true
        errorMessage = nil
        defer { isLoadingFriends = false }
        do {
            let page = try await SocialService.fetchFriends(limit: 50, offset: 0)
            friends = page.items
        } catch {
            errorMessage = error.localizedDescription
            friends = []
        }
    }

    /// Opportunistic, Wi-Fi-gated: warm the avatars the Friends tab will show
    /// (pending requests + friends) so the list renders without pop-in. Call
    /// after `loadPending()`/`loadFriends()`. Matches `SocialAvatarView`'s URL
    /// normalization so the cache keys line up.
    func prewarmAvatars(max: Int = 30) {
        var urls: [URL] = []
        var seen = Set<String>()
        func add(_ raw: String?) {
            guard urls.count < max, let raw, !raw.isEmpty,
                  let url = URL(string: raw.normalizedAsHTTPURLString),
                  seen.insert(url.absoluteString).inserted else { return }
            urls.append(url)
        }
        pendingData?.incomingFriendRequests.forEach { add($0.user.avatarUrl) }
        pendingData?.outgoingFriendRequests.forEach { add($0.user.avatarUrl) }
        friends.forEach { add($0.avatarUrl) }
        for url in urls { ImageCacheService.shared.preload(from: url) }
    }

    func onSearchTextChanged() {
        searchDebounceTask?.cancel()
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchResults = []
            isSearching = false
            searchGeneration += 1
            return
        }
        guard trimmed.count >= 1 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchGeneration += 1
        let generation = searchGeneration
        let query = trimmed
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch(query: query, generation: generation)
        }
    }

    private func performSearch(query: String, generation: Int) async {
        errorMessage = nil
        do {
            let items = try await SocialService.searchUsers(query: query, limit: 20)
            guard generation == searchGeneration else { return }
            searchResults = items
        } catch {
            guard generation == searchGeneration else { return }
            errorMessage = error.localizedDescription
            searchResults = []
        }
        guard generation == searchGeneration else { return }
        isSearching = false
    }

    // MARK: - Pending actions (also used from PendingRequestsView)

    func acceptFriendRequest(fromUserId: String) async {
        errorMessage = nil
        do {
            _ = try await SocialService.acceptFriendRequest(fromUserId: fromUserId)
            removeIncomingFriendRequest(fromUserId: fromUserId)
            await loadFriends()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineFriendRequest(fromUserId: String) async {
        errorMessage = nil
        do {
            _ = try await SocialService.declineFriendRequest(fromUserId: fromUserId)
            removeIncomingFriendRequest(fromUserId: fromUserId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelOutgoingFriendRequest(userId: String) async {
        errorMessage = nil
        do {
            _ = try await SocialService.cancelFriendRequest(userId: userId)
            removeOutgoingFriendRequest(userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeIncomingFriendRequest(fromUserId: String) {
        guard var data = pendingData else { return }
        data.incomingFriendRequests.removeAll { $0.user.id == fromUserId }
        pendingData = data
    }

    private func removeOutgoingFriendRequest(userId: String) {
        guard var data = pendingData else { return }
        data.outgoingFriendRequests.removeAll { $0.user.id == userId }
        pendingData = data
    }

    func removeFriend(userId: String) async {
        errorMessage = nil
        do {
            _ = try await SocialService.removeFriend(userId: userId)
            friends.removeAll { $0.id == userId }
            await loadPending()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
