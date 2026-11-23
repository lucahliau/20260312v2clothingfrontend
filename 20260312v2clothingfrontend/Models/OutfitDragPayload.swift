import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist under UTExportedTypeDeclarations.
    static let wardrobeItem = UTType(exportedAs: "app.wardrobe.item")
}

/// Drag payload for saved items (grid tile → a collection stack in the
/// drawer). Carries just the `SwipeRecord.id`; the drop handler looks the
/// record up by id.
struct WardrobeItemPayload: Codable, Transferable {
    let recordId: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .wardrobeItem)
    }
}
