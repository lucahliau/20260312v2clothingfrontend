import SwiftUI

struct MainTabView: View {
    @State private var feedViewModel = FeedViewModel()
    @State private var swipeHistoryViewModel = SwipeHistoryViewModel()
    @State private var wardrobeViewModel = WardrobeViewModel()
    @State private var exploreViewModel = ExploreViewModel()
    @State private var friendsViewModel = FriendsViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var didStartSessionWarmup = false

    var body: some View {
        TabView {
            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Feed", systemImage: "rectangle.stack")
            }

            NavigationStack {
                ExploreView()
            }
            .tabItem {
                Label("Explore", systemImage: "sparkles")
            }

            NavigationStack {
                WardrobeHomeView()
            }
            .tabItem {
                Label("Wardrobe", systemImage: "hanger")
            }

            NavigationStack {
                FriendsView()
            }
            .tabItem {
                Label("Friends", systemImage: "person.2")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .environment(feedViewModel)
        .environment(swipeHistoryViewModel)
        .environment(wardrobeViewModel)
        .environment(exploreViewModel)
        .environment(friendsViewModel)
        .environment(settingsViewModel)
        // Verify-later nag, pinned just above the tab bar on every tab.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VerifyEmailBanner()
        }
        .onAppear {
            guard !didStartSessionWarmup else { return }
            didStartSessionWarmup = true
            Task(priority: .utility) {
                try? await Task.sleep(for: .milliseconds(400))
                await settingsViewModel.loadProfileIfNeeded()
                try? await Task.sleep(for: .milliseconds(80))
                await swipeHistoryViewModel.loadPreviewIfNeeded()
                try? await Task.sleep(for: .milliseconds(80))
                await exploreViewModel.loadFeaturedIfNeeded()
                try? await Task.sleep(for: .milliseconds(80))
                await friendsViewModel.loadPending()
            }
        }
    }
}
