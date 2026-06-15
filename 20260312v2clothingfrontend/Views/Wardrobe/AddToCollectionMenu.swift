import SwiftUI

/// Long-press context menu for filing a closet item into a collection — the
/// discoverable sibling of drag-and-dropping onto a stack in the drawer.
struct AddToCollectionMenuModifier: ViewModifier {
    let recordId: String
    @Environment(WardrobeViewModel.self) private var wardrobeViewModel
    @Environment(SwipeHistoryViewModel.self) private var historyViewModel

    func body(content: Content) -> some View {
        content.contextMenu {
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
                                    from: historyViewModel.records,
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
}

extension View {
    /// Attach the "Add to collection" long-press menu to any closet item view.
    func addToCollectionMenu(recordId: String) -> some View {
        modifier(AddToCollectionMenuModifier(recordId: recordId))
    }
}
