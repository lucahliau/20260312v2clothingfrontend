import Foundation

enum AuthService {
    static func register(email: String, username: String, password: String) async throws -> AuthResponse {
        let body = RegisterRequest(
            email: email,
            username: username,
            password: password,
            deviceId: KeychainManager.deviceId()
        )
        return try await NetworkManager.shared.request(
            "/auth/register",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    /// `identifier` may be an email or a username — the backend accepts both.
    static func login(identifier: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(
            username: identifier,
            password: password,
            deviceId: KeychainManager.deviceId()
        )
        return try await NetworkManager.shared.request(
            "/auth/login",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    /// Tells the server to drop this device's session. Takes the tokens
    /// explicitly because the caller has already wiped the keychain; goes
    /// straight through URLSession (no token refresh, no session-expired
    /// side effects) with a short timeout. Failures are ignored — the
    /// local logout has already happened.
    static func logoutBestEffort(accessToken: String?, refreshToken: String?) {
        guard let accessToken,
              let url = URL(string: NetworkManager.shared.baseURL + "/auth/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(
            LogoutRequest(refreshToken: refreshToken, deviceId: KeychainManager.deviceId())
        )
        Task.detached(priority: .utility) {
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    static func signInWithApple(identityToken: String, fullName: AppleFullName? = nil) async throws -> AuthResponse {
        let body = AppleSignInRequest(
            identityToken: identityToken,
            fullName: fullName,
            deviceId: KeychainManager.deviceId()
        )
        return try await NetworkManager.shared.request(
            "/auth/apple",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    static func changePassword(currentPassword: String, newPassword: String) async throws -> ChangePasswordResponse {
        let body = ChangePasswordRequest(
            currentPassword: currentPassword,
            newPassword: newPassword,
            deviceId: KeychainManager.deviceId()
        )
        return try await NetworkManager.shared.request(
            "/auth/change-password",
            method: "POST",
            body: body
        )
    }
}
