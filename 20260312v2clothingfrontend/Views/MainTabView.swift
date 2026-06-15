import SwiftUI
import UserNotifications

enum MainTab: String, Hashable {
    case feed, explore, wardrobe, friends, settings
}

/// Cross-tab navigation: any view can switch the selected tab (e.g. the empty
/// wardrobe's "Browse the Feed" button).
@Observable
final class TabRouter {
    var selectedTab: MainTab

    init() {
        #if DEBUG
        // Screenshot hook: SIMCTL_CHILD_DEMO_TAB=wardrobe opens on that tab.
        if let raw = ProcessInfo.processInfo.environment["DEMO_TAB"],
           let tab = MainTab(rawValue: raw) {
            selectedTab = tab
            return
        }
        #endif
        selectedTab = .feed
    }
}

struct MainTabView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var feedViewModel = FeedViewModel()
    @State private var swipeHistoryViewModel = SwipeHistoryViewModel()
    @State private var wardrobeViewModel = WardrobeViewModel()
    @State private var exploreViewModel = ExploreViewModel()
    @State private var friendsViewModel = FriendsViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var didStartSessionWarmup = false
    @State private var tabRouter = TabRouter()

    var body: some View {
        @Bindable var tabRouter = tabRouter
        TabView(selection: $tabRouter.selectedTab) {
            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Feed", systemImage: "rectangle.stack")
            }
            .tag(MainTab.feed)

            NavigationStack {
                ExploreView()
            }
            .tabItem {
                Label("Explore", systemImage: "sparkles")
            }
            .tag(MainTab.explore)

            NavigationStack {
                WardrobeHomeView()
            }
            .tabItem {
                Label("Wardrobe", systemImage: "hanger")
            }
            .tag(MainTab.wardrobe)

            NavigationStack {
                FriendsView()
            }
            .tabItem {
                Label("Friends", systemImage: "person.2")
            }
            .tag(MainTab.friends)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(MainTab.settings)
        }
        .environment(feedViewModel)
        .environment(swipeHistoryViewModel)
        .environment(wardrobeViewModel)
        .environment(exploreViewModel)
        .environment(friendsViewModel)
        .environment(settingsViewModel)
        .environment(tabRouter)
        // Verify-later nag, pinned just above the tab bar on every tab.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VerifyEmailBanner()
        }
        // First-run calibration: stays up until the server (or skip) marks
        // onboarding complete.
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingView()
                .environment(settingsViewModel)
        }
        // Screen-view analytics: which tabs users actually visit.
        .onChange(of: tabRouter.selectedTab) { _, newTab in
            AnalyticsManager.shared.track("screen_view", screen: newTab.rawValue)
        }
        .onAppear {
            guard !didStartSessionWarmup else { return }
            didStartSessionWarmup = true
            // Record the tab the app opens on (.onChange only fires on switches).
            AnalyticsManager.shared.track("screen_view", screen: tabRouter.selectedTab.rawValue)
            ConnectivityMonitor.shared.start()
            UNUserNotificationCenter.current().setBadgeCount(0)
            Task(priority: .utility) {
                // Replay swipes queued while offline, then ship any crash
                // reports MetricKit delivered for the previous run. Profile is
                // small and the feed's default gender filter depends on it.
                await PendingSwipeQueue.shared.flush()
                await CrashReportService.uploadPending()
                try? await Task.sleep(for: .milliseconds(400))
                await settingsViewModel.loadProfileIfNeeded()
            }
            Task(priority: .background) {
                // Everything else waits out the launch interaction window —
                // the feed fetch + first card images own the first seconds,
                // and these loads were causing tab-bar hitches on older
                // devices when they ran during it.
                try? await Task.sleep(for: .seconds(3))
                // History data also feeds the Wardrobe rails, so loading it
                // warms most wardrobe images for free.
                await swipeHistoryViewModel.loadPreviewIfNeeded()
                try? await Task.sleep(for: .milliseconds(80))
                await friendsViewModel.loadPending()
                await friendsViewModel.loadFriends()
                // Notifications — permission prompt + daily nudges, then the
                // friends-hot-items check (no-ops if denied/unavailable).
                await NotificationsManager.setupAfterLogin()
                await NotificationsManager.checkFriendsHotItems()
                // Cheap tab data (collections) regardless of network so layouts
                // are ready; defer the heavier image prewarm below.
                await wardrobeViewModel.loadCollectionsIfNeeded()
                // Explore featured last: it downloads + decodes a collage of
                // images to validate them. ExploreView also triggers this on
                // appear, so opening the tab early just loads it there.
                try? await Task.sleep(for: .seconds(2))
                await exploreViewModel.loadFeaturedIfNeeded()
                // Opportunistic image prewarm for the other tabs — Wi-Fi /
                // unconstrained networks only, so we never spend the user's
                // cellular data warming tabs they may not open.
                if ConnectivityMonitor.shared.allowsHeavyPrefetch {
                    friendsViewModel.prewarmAvatars()
                    await wardrobeViewModel.prewarmImages()
                }
            }
        }
    }

    /// Dismissal only flows through `completeOnboarding()` — the cover itself
    /// can't be swiped away.
    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { authViewModel.needsOnboarding },
            set: { presented in
                if !presented { authViewModel.completeOnboarding() }
            }
        )
    }
}
