import SwiftUI

/// The "Add to collection" entries for a saved item's long-press menu — the
/// discoverable sibling of drag-and-dropping onto a stack in the drawer.
/// A plain view so hosts can combine it with their own menu actions.
struct AddToCollectionMenuItems: View {
    let recordId: String
    @Environment(WardrobeViewModel.self) private var wardrobeViewModel
    @Environment(SwipeHistoryViewModel.self) private var historyViewModel

    var body: some View {
        if wardrobeViewModel.collections.isEmpty {
            Button {} label: {
                Label("No collections yet — open the drawer below to create one", systemImage: "tray")
            }
            .disabled(true)
        } else {
            Section("Add to collection") {
                ForEach(wardrobeViewModel.collections) { collection in
                    Button {
                        Task {
                            _ = await wardrobeViewModel.addRecord(
                                withId: recordId,
                                from: historyViewModel.likedRecords,
                                to: collection
                            )
                        }
                    } label: {
                        Label(collection.name, systemImage: "tray.full")
                    }
                }
            }
        }
    }
}

struct AddToCollectionMenuModifier: ViewModifier {
    let recordId: String

    func body(content: Content) -> some View {
        content.contextMenu {
            AddToCollectionMenuItems(recordId: recordId)
        }
    }
}

extension View {
    /// Attach the "Add to collection" long-press menu to any closet item view.
    func addToCollectionMenu(recordId: String) -> some View {
        modifier(AddToCollectionMenuModifier(recordId: recordId))
    }
}
