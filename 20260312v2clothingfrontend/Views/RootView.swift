import SwiftUI

struct RootView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                MainTabView()
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appPrimaryText)
            } else {
                AuthView()
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appOnHalftonePrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .tint(Color.appAccent)
        .animation(.easeInOut(duration: 0.3), value: authViewModel.isAuthenticated)
    }
}
