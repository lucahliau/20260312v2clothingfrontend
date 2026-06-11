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

    static func logout() async throws {
        // Send the current refresh token so the server can delete *this*
        // device's session row rather than relying on the per-device fallback
        // alone. Best-effort: missing token is OK on the server side.
        let body = LogoutRequest(
            refreshToken: KeychainManager.read(key: KeychainManager.refreshTokenKey),
            deviceId: KeychainManager.deviceId()
        )
        try await NetworkManager.shared.requestVoid(
            "/auth/logout",
            method: "POST",
            body: body,
            authenticated: true
        )
    }

    static func forgotPassword(email: String) async throws {
        let body = ForgotPasswordRequest(email: email)
        try await NetworkManager.shared.requestVoid(
            "/auth/forgot-password",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    static func resetPassword(token: String, password: String) async throws {
        let body = ResetPasswordRequest(token: token, password: password)
        try await NetworkManager.shared.requestVoid(
            "/auth/reset-password",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    /// Always 200 on the server (no account enumeration) — safe to call freely.
    static func resendVerification(email: String) async throws {
        let body = ResendVerificationRequest(email: email)
        try await NetworkManager.shared.requestVoid(
            "/auth/resend-verification",
            method: "POST",
            body: body,
            authenticated: false
        )
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
