import Foundation

struct LoginRequest: Codable, Sendable {
    let username: String
    let password: String
    let deviceId: String
}

struct RegisterRequest: Codable, Sendable {
    let email: String
    let username: String
    let password: String
    let deviceId: String
}

struct RefreshRequest: Codable, Sendable {
    let refreshToken: String
    let deviceId: String
}

struct LogoutRequest: Codable, Sendable {
    let refreshToken: String?
    let deviceId: String
}

/// Tokens are optional defensively: a backend running the old verify-first
/// policy returned register responses without them.
struct AuthResponse: Codable, Sendable {
    let user: User?
    let accessToken: String?
    let refreshToken: String?
    let isNewUser: Bool?
    let requiresEmailVerification: Bool?
}

struct TokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct APIErrorResponse: Codable, Sendable {
    let error: APIErrorBody
}

struct APIErrorBody: Codable, Sendable {
    let code: String
    let message: String
    let details: [String: [String]]?
}

// MARK: - Additional Auth Requests

struct ForgotPasswordRequest: Codable, Sendable {
    let email: String
}

struct ResetPasswordRequest: Codable, Sendable {
    let token: String
    let password: String
}

struct ResendVerificationRequest: Codable, Sendable {
    let email: String
}

/// Matches the backend's `appleAuthSchema`: { identityToken, fullName?, deviceId? }.
struct AppleSignInRequest: Codable, Sendable {
    let identityToken: String
    let fullName: AppleFullName?
    let deviceId: String
}

struct AppleFullName: Codable, Sendable {
    let givenName: String?
    let familyName: String?
}

struct ChangePasswordRequest: Codable, Sendable {
    let currentPassword: String
    let newPassword: String
    /// Lets the server re-issue a session for this device after it revokes all
    /// sessions (the security behavior of a password change).
    let deviceId: String
}

/// Change-password revokes every session; the server re-issues fresh tokens
/// for the requesting device so the user isn't logged out mid-action.
struct ChangePasswordResponse: Codable, Sendable {
    let message: String
    let accessToken: String?
    let refreshToken: String?
}
