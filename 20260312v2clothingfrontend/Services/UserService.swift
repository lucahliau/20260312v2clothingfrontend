import Foundation

enum UserService {
    static func fetchCurrentUser() async throws -> User {
        try await NetworkManager.shared.request("/users/me")
    }

    static func updateProfile(_ update: UserUpdateRequest) async throws -> User {
        try await NetworkManager.shared.request(
            "/users/me",
            method: "PATCH",
            body: update
        )
    }

    static func deleteAccount() async throws {
        try await NetworkManager.shared.requestVoid(
            "/users/me",
            method: "DELETE"
        )
    }

    static func saveOnboarding(_ onboarding: OnboardingRequest) async throws -> User {
        try await NetworkManager.shared.request(
            "/users/me/onboarding",
            method: "POST",
            body: onboarding
        )
    }

    static func getAvatarUploadUrl(fileExt: String? = nil) async throws -> AvatarUploadUrlResponse {
        let body = AvatarUploadURLRequest(fileExt: fileExt)
        return try await NetworkManager.shared.request(
            "/users/me/avatar-upload-url",
            method: "POST",
            body: body
        )
    }

    static func updateAvatarUrl(_ publicUrl: String) async throws -> User {
        try await NetworkManager.shared.request(
            "/users/me",
            method: "PATCH",
            body: AvatarUrlUpdateRequest(avatarUrl: publicUrl)
        )
    }

    static func registerDeviceToken(_ token: String) async throws {
        let body = DeviceTokenRequest(token: token)
        try await NetworkManager.shared.requestVoid(
            "/users/me/device-tokens",
            method: "POST",
            body: body
        )
    }

    static func removeDeviceToken(_ token: String) async throws {
        try await NetworkManager.shared.requestVoid(
            "/users/me/device-tokens/\(token)",
            method: "DELETE"
        )
    }
}
