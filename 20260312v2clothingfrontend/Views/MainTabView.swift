import SwiftUI

struct MainTabView: View {
    @State private var feedViewModel = FeedViewModel()
    @State private var swipeHistoryViewModel = SwipeHistoryViewModel()
    @State private var exploreViewModel = ExploreViewModel()
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
                SwipeHistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                ExploreView()
            }
            .tabItem {
                Label("Explore", systemImage: "sparkles")
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
        .environment(exploreViewModel)
        .environment(settingsViewModel)
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
            }
        }
    }
}
