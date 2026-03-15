import Foundation
import Observation

@Observable
final class FeedViewModel {
    var items: [Item] = []
    var isLoading = false
    var errorMessage: String?

    func loadItems() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await ItemService.fetchItems()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
