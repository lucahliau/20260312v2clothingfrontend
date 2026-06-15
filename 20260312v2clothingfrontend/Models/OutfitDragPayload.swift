import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// One Transferable per `OutfitSlot` so SwiftUI's `.dropDestination(for:)` can natively filter
/// which slots accept which garment — a hat-payload only highlights/drops on the hat slot, etc.
/// Distinct UTTypes (declared in Info.plist under UTExportedTypeDeclarations) give the system
/// the identifier-equality match it uses for filtering. The payload itself carries just the
/// `SwipeRecord.id`; the parent looks the record up by id when handling the drop.

extension UTType {
    static let outfitHat = UTType(exportedAs: "app.wardrobe.outfit-hat")
    static let outfitTop = UTType(exportedAs: "app.wardrobe.outfit-top")
    static let outfitBottoms = UTType(exportedAs: "app.wardrobe.outfit-bottoms")
    static let outfitShoes = UTType(exportedAs: "app.wardrobe.outfit-shoes")
    static let wardrobeItem = UTType(exportedAs: "app.wardrobe.item")
}

/// Slot-agnostic payload for Closet drags (any item → a collection stack in the
/// drawer). The slot-typed payloads below stay for the Fitting Room, where the
/// type IS the drop filter.
struct WardrobeItemPayload: Codable, Transferable {
    let recordId: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .wardrobeItem)
    }
}

struct HatDragPayload: Codable, Transferable {
    let recordId: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .outfitHat)
    }
}

struct TopDragPayload: Codable, Transferable {
    let recordId: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .outfitTop)
    }
}

struct BottomsDragPayload: Codable, Transferable {
    let recordId: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .outfitBottoms)
    }
}

struct ShoesDragPayload: Codable, Transferable {
    let recordId: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .outfitShoes)
    }
}
