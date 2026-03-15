import Foundation

struct CollectionCount: Codable, Sendable {
    let items: Int
}

struct Collection: Codable, Sendable, Identifiable {
    let id: String
    let userId: String?
    let name: String
    let coverUrl: String?
    let createdAt: String?
    let updatedAt: String?
    let _count: CollectionCount?
}

struct CollectionItem: Codable, Sendable, Identifiable {
    let id: String
    let collectionId: String
    let itemId: String
    let addedAt: String?
    let item: Item
}

struct CollectionDetail: Codable, Sendable {
    let id: String
    let userId: String?
    let name: String
    let coverUrl: String?
    let createdAt: String?
    let updatedAt: String?
    let items: [CollectionItem]
}

struct CreateCollectionRequest: Codable, Sendable {
    let name: String
}

struct UpdateCollectionRequest: Codable, Sendable {
    var name: String?
    var coverUrl: String?
}

struct AddItemToCollectionRequest: Codable, Sendable {
    let itemId: String
}
