import Combine
import SwiftUI

private struct PasswordResetPresentation: Identifiable {
    let id = UUID()
    let token: String
}

struct RootView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var passwordResetPresentation: PasswordResetPresentation?
    @State private var showInvalidPasswordResetLinkAlert = false

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
        .fullScreenCover(item: $passwordResetPresentation) { presentation in
            ResetPasswordFromLinkView(token: presentation.token) {
                passwordResetPresentation = nil
            }
        }
        .alert("Invalid reset link", isPresented: $showInvalidPasswordResetLinkAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This password reset link is missing a token. Request a new reset email and open the link from your inbox.")
        }
        .onOpenURL { url in
            handlePasswordResetURL(url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL {
                handlePasswordResetURL(url)
            }
        }
        // Validate the stored token once per launch (only a real 401 logs out;
        // offline launches keep the session) and pull fresh account state.
        .task {
            #if DEBUG
            await authViewModel.demoLoginIfRequested()
            #endif
            await authViewModel.checkSession()
        }
        // NetworkManager posts this exactly when the server rejects our
        // refresh token mid-session — flip the gate with an explanation
        // instead of silently bouncing to the login screen.
        .onReceive(
            NotificationCenter.default.publisher(for: .authSessionExpired)
                .receive(on: DispatchQueue.main)
        ) { _ in
            authViewModel.handleSessionExpired()
        }
        // Usage-analytics session boundaries. .active starts a session (no-op
        // if one is already running, so brief .inactive flickers don't split
        // it); .background ends it and flushes. Tied to the always-present
        // RootView so it covers both logged-in and logged-out usage.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: AnalyticsManager.shared.startSession()
            case .background:
                AnalyticsManager.shared.endSession()
                // Ship any swipes still sitting under the debounce timer before
                // the app suspends. They're persisted regardless, so a missed
                // flush just retries on next launch (MainTabView) — never lost.
                Task { await PendingSwipeQueue.shared.flush() }
            default: break
            }
        }
    }

    private func handlePasswordResetURL(_ url: URL) {
        if let token = PasswordResetURL.token(from: url) {
            passwordResetPresentation = PasswordResetPresentation(token: token)
            return
        }
        if PasswordResetURL.looksLikePasswordResetURL(url) {
            showInvalidPasswordResetLinkAlert = true
        }
    }
}
