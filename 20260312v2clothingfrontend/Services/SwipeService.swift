import Foundation

/// Wire body for `POST /swipes/batch`. `nonisolated` (and `action` as a raw
/// string) because the queue encodes these from inside the `PendingSwipeQueue`
/// actor — a MainActor-isolated `Codable` conformance can't be used there
/// (a hard error in Swift 6). The backend's zod enum accepts the plain string.
private nonisolated struct SwipeBatchItem: Codable, Sendable {
    let itemId: String
    let action: String
}

private nonisolated struct SwipeBatchBody: Codable, Sendable {
    let swipes: [SwipeBatchItem]
}

enum SwipeService {
    /// Records a swipe (love, like, dislike, or neutral) on an item. When the
    /// device is offline the swipe is queued to disk and replayed once
    /// connectivity returns — the caller sees success either way, so the feed
    /// keeps moving in the subway.
    static func recordSwipe(itemId: String, type: SwipeType) async throws {
        do {
            try await postSwipe(itemId: itemId, type: type)
        } catch let error where error.isOfflineConnectivityError {
            await PendingSwipeQueue.shared.enqueue(itemId: itemId, action: type)
        }
    }

    /// Raw POST without offline queueing — used by `recordSwipe` and the
    /// queue's replay (which must not re-enqueue on failure).
    static func postSwipe(itemId: String, type: SwipeType) async throws {
        let body = SwipeRequest(itemId: itemId, action: type)
        do {
            try await NetworkManager.shared.requestVoid(
                "/swipes",
                method: "POST",
                body: body
            )
        } catch NetworkError.serverError(let statusCode, _, _) where statusCode == 409 {
            // "Already swiped" from a pre-upsert backend: the swipe exists, so
            // treat it as success — surfacing the error re-presents the same
            // card and traps the user in a swipe → 409 → swipe loop.
        }
    }

    /// Records many swipes in one request via `POST /swipes/batch` — used by the
    /// disk-backed queue so rapid swiping is one network call per batch, never
    /// one per swipe (which trips the per-swipe rate limit). Falls back to
    /// per-swipe POSTs if the backend lacks the batch endpoint (404), so an
    /// older deploy never strands queued swipes.
    static func postSwipeBatch(_ swipes: [(itemId: String, action: SwipeType)]) async throws {
        guard !swipes.isEmpty else { return }
        let body = SwipeBatchBody(
            swipes: swipes.map { SwipeBatchItem(itemId: $0.itemId, action: $0.action.rawValue) }
        )
        do {
            try await NetworkManager.shared.requestVoid("/swipes/batch", method: "POST", body: body)
        } catch NetworkError.serverError(let statusCode, _, _) where statusCode == 404 {
            for swipe in swipes {
                try await postSwipe(itemId: swipe.itemId, type: swipe.action)
            }
        }
    }

    /// One page of swipe history, newest first, with the server's pagination
    /// block. `actions` narrows to those swipe types (the Wardrobe passes
    /// LOVE + LIKE); `nil` returns every action.
    static func fetchSwipeHistoryPage(
        page: Int,
        limit: Int,
        actions: [SwipeType]? = nil
    ) async throws -> PaginatedSwipesResponse {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let actions, !actions.isEmpty {
            queryItems.append(
                URLQueryItem(name: "action", value: actions.map(\.rawValue).joined(separator: ","))
            )
        }
        return try await NetworkManager.shared.request("/swipes/history", queryItems: queryItems)
    }

    /// Undoes the most recent swipe.
    static func undoLastSwipe() async throws {
        try await NetworkManager.shared.requestVoid(
            "/swipes/last",
            method: "DELETE"
        )
    }

    /// Updates an existing swipe record's action.
    static func updateSwipe(swipeId: String, action: SwipeType) async throws -> SwipeRecord {
        let body = UpdateSwipeRequest(action: action)
        return try await NetworkManager.shared.request(
            "/swipes/\(swipeId)",
            method: "PATCH",
            body: body
        )
    }
}
