import Foundation
import Observation
import AuthenticationServices

@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    // Verify-later email state — drives the banner and the Settings email row.
    var needsEmailVerification = false
    var verifyBannerDismissed = false

    /// True until the server reports `onboardingCompleted` — RootView presents
    /// the calibration flow while this is set.
    var needsOnboarding = false
    enum ResendState: Equatable { case idle, sending, sent }
    var resendState: ResendState = .idle
    private(set) var currentEmail: String?
    /// Launch `/users/me` result shared with Settings so it is not fetched twice.
    private(set) var currentUser: User?

    init() {
        isAuthenticated = KeychainManager.read(key: KeychainManager.accessTokenKey) != nil
    }

    /// Launch-time validation: confirms the stored token still works and pulls
    /// fresh account state (e.g. emailVerified). Only a real 401 logs out —
    /// an offline launch keeps the session.
    func checkSession() async {
        guard KeychainManager.read(key: KeychainManager.accessTokenKey) != nil else {
            isAuthenticated = false
            return
        }
        do {
            let user: User = try await NetworkManager.shared.request("/users/me")
            apply(user: user)
            isAuthenticated = true
        } catch NetworkError.unauthorized {
            KeychainManager.clearTokens()
            isAuthenticated = false
        } catch {
            // Transient (offline, 5xx): never log the user out for connectivity.
        }
    }

    /// Re-pulls emailVerified — called when the app foregrounds while the
    /// banner is showing (the user likely just tapped the email link).
    func refreshVerificationStatus() async {
        guard isAuthenticated, needsEmailVerification else { return }
        if let user: User = try? await NetworkManager.shared.request("/users/me") {
            apply(user: user)
        }
    }

    func login(identifier: String, password: String) async {
        let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email or username and your password."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await AuthService.login(identifier: id, password: password)
            applyAuthResponse(response)
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .login)
        }
        isLoading = false
    }

    func register(email: String, username: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }
        guard trimmedUsername.count >= 3 else {
            errorMessage = "Username must be at least 3 characters."
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await AuthService.register(
                email: trimmedEmail,
                username: trimmedUsername,
                password: password
            )
            applyAuthResponse(response)
        } catch {
            errorMessage = AuthErrorMapper.message(for: error, context: .register)
        }
        isLoading = false
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            // A user-cancelled sheet is not an error.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled { return }
            errorMessage = "Apple sign-in didn't complete. Try again."
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple sign-in didn't return a valid credential. Try again."
                return
            }
            isLoading = true
            errorMessage = nil
            // Apple only provides the name on the FIRST authorization — forward
            // it so the new account gets it.
            let fullName = AppleFullName(
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName
            )
            do {
                let response = try await AuthService.signInWithApple(
                    identityToken: identityToken,
                    fullName: fullName
                )
                applyAuthResponse(response)
            } catch {
                errorMessage = AuthErrorMapper.message(for: error, context: .login)
            }
            isLoading = false
        }
    }

    /// Banner action. The endpoint never reveals whether the email exists, so
    /// "sent" simply means the request went through.
    func resendVerificationEmail() async {
        guard let email = currentEmail else { return }
        resendState = .sending
        do {
            try await AuthService.resendVerification(email: email)
            resendState = .sent
        } catch {
            resendState = .idle
        }
    }

    /// Returns nil on success, or a user-facing error message. On success the
    /// server has revoked every session and re-issued tokens for this device.
    func changePassword(currentPassword: String, newPassword: String) async -> String? {
        do {
            let response = try await AuthService.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            if let access = response.accessToken, let refresh = response.refreshToken {
                KeychainManager.save(key: KeychainManager.accessTokenKey, data: access)
                KeychainManager.save(key: KeychainManager.refreshTokenKey, data: refresh)
            }
            return nil
        } catch {
            return AuthErrorMapper.message(for: error, context: .changePassword)
        }
    }

    /// Returns nil on success (the auth gate flips), or a user-facing error.
    func deleteAccount() async -> String? {
        do {
            try await UserService.deleteAccount()
            KeychainManager.clearTokens()
            resetAccountState()
            isAuthenticated = false
            NotificationsManager.cancelAll()
            return nil
        } catch {
            return AuthErrorMapper.message(for: error)
        }
    }

    func logout() async {
        // Before the session dies: stop remote pushes to this device.
        await PushRegistrationService.unregisterCurrentToken()
        try? await AuthService.logout()
        KeychainManager.clearTokens()
        resetAccountState()
        isAuthenticated = false
        NotificationsManager.cancelAll()
    }

    /// Called by OnboardingView once the calibration answers are saved (or skipped).
    func completeOnboarding() {
        needsOnboarding = false
        AnalyticsManager.shared.track("onboarding_complete")
    }

    #if DEBUG
    /// Dev/screenshot hook: `SIMCTL_CHILD_DEMO_EMAIL` / `_DEMO_PASSWORD` on a
    /// simulator launch logs straight in. Compiled out of release builds.
    func demoLoginIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        print("[demo] hook reached. DEMO_EMAIL=\(env["DEMO_EMAIL"] ?? "nil") authed=\(isAuthenticated)")
        guard !isAuthenticated,
              let email = env["DEMO_EMAIL"],
              let password = env["DEMO_PASSWORD"] else { return }
        await login(identifier: email, password: password)
        print("[demo] login finished. authed=\(isAuthenticated) error=\(errorMessage ?? "none")")
    }
    #endif

    /// Called from RootView when NetworkManager reports real session death.
    func handleSessionExpired() {
        guard isAuthenticated else { return }
        resetAccountState()
        isAuthenticated = false
        errorMessage = "Your session expired. Please log in again."
    }

    // MARK: - Private

    private func applyAuthResponse(_ response: AuthResponse) {
        guard let access = response.accessToken, let refresh = response.refreshToken else {
            // Old verify-first backend: the account exists but can't log in yet.
            errorMessage = "Account created — check your email, then log in."
            return
        }
        KeychainManager.save(key: KeychainManager.accessTokenKey, data: access)
        KeychainManager.save(key: KeychainManager.refreshTokenKey, data: refresh)
        if let user = response.user {
            apply(user: user)
        }
        verifyBannerDismissed = false
        resendState = .idle
        errorMessage = nil
        isAuthenticated = true
    }

    private func apply(user: User) {
        currentUser = user
        currentEmail = user.email
        needsEmailVerification = !(user.emailVerified ?? true)
        needsOnboarding = !user.onboardingCompleted
    }

    private func resetAccountState() {
        currentUser = nil
        currentEmail = nil
        needsEmailVerification = false
        verifyBannerDismissed = false
        resendState = .idle
        needsOnboarding = false
    }
}
