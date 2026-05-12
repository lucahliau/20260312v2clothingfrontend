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

struct AuthResponse: Codable, Sendable {
    let user: User?
    let accessToken: String
    let refreshToken: String
    let isNewUser: Bool?
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

struct AppleSignInRequest: Codable, Sendable {
    let identityToken: String
    let authorizationCode: String?
    let user: AppleUser?
    let deviceId: String
}

struct AppleUser: Codable, Sendable {
    let email: String?
    let name: AppleUserName?
}

struct AppleUserName: Codable, Sendable {
    let firstName: String?
    let lastName: String?
}

struct ChangePasswordRequest: Codable, Sendable {
    let currentPassword: String
    let newPassword: String
}
