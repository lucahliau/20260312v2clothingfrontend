import Foundation

enum CollectionService {
    /// Lists the authenticated user's collections.
    static func fetchCollections() async throws -> [Collection] {
        try await NetworkManager.shared.request("/collections")
    }

    /// Creates a new collection.
    static func createCollection(name: String) async throws -> Collection {
        let body = CreateCollectionRequest(name: name)
        return try await NetworkManager.shared.request(
            "/collections",
            method: "POST",
            body: body
        )
    }

    /// Returns a collection and its items.
    static func fetchCollection(id: String) async throws -> CollectionDetail {
        try await NetworkManager.shared.request("/collections/\(id)")
    }

    /// Updates a collection (name, cover).
    static func updateCollection(id: String, update: UpdateCollectionRequest) async throws -> Collection {
        try await NetworkManager.shared.request(
            "/collections/\(id)",
            method: "PATCH",
            body: update
        )
    }

    /// Deletes a collection.
    static func deleteCollection(id: String) async throws {
        try await NetworkManager.shared.requestVoid(
            "/collections/\(id)",
            method: "DELETE"
        )
    }

    /// Adds an item to a collection.
    static func addItemToCollection(collectionId: String, itemId: String) async throws {
        let body = AddItemToCollectionRequest(itemId: itemId)
        try await NetworkManager.shared.requestVoid(
            "/collections/\(collectionId)/items",
            method: "POST",
            body: body
        )
    }

    /// Removes an item from a collection.
    static func removeItemFromCollection(collectionId: String, itemId: String) async throws {
        try await NetworkManager.shared.requestVoid(
            "/collections/\(collectionId)/items/\(itemId)",
            method: "DELETE"
        )
    }
}
