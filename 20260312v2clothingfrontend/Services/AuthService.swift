import Foundation

enum AuthService {
    static func register(email: String, username: String, password: String) async throws -> AuthResponse {
        let body = RegisterRequest(email: email, username: username, password: password)
        return try await NetworkManager.shared.request(
            "/auth/register",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    static func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password)
        return try await NetworkManager.shared.request(
            "/auth/login",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    static func logout() async throws {
        try await NetworkManager.shared.requestVoid(
            "/auth/logout",
            method: "POST",
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

    static func resetPassword(token: String, newPassword: String) async throws {
        let body = ResetPasswordRequest(token: token, newPassword: newPassword)
        try await NetworkManager.shared.requestVoid(
            "/auth/reset-password",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    static func signInWithApple(identityToken: String, authorizationCode: String? = nil, user: AppleUser? = nil) async throws -> AuthResponse {
        let body = AppleSignInRequest(identityToken: identityToken, authorizationCode: authorizationCode, user: user)
        return try await NetworkManager.shared.request(
            "/auth/apple",
            method: "POST",
            body: body,
            authenticated: false
        )
    }

    static func changePassword(currentPassword: String, newPassword: String) async throws {
        let body = ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword)
        try await NetworkManager.shared.requestVoid(
            "/auth/change-password",
            method: "POST",
            body: body
        )
    }
}
