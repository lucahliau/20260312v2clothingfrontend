import SwiftUI

/// Wardrobe tab entry point — opens straight into the Closet. (The Fitting
/// Room composer is parked for now; its views remain but nothing links to it.)
struct WardrobeHomeView: View {
    var body: some View {
        ClosetView()
    }
}
