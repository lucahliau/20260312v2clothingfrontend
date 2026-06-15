import Foundation

struct User: Codable, Sendable {
    let id: String
    let username: String
    let email: String
    var firstName: String?
    var lastName: String?
    var avatarUrl: String?
    var bio: String?
    var onboardingCompleted: Bool
    var emailVerified: Bool?
    var stylePreferences: [String]
    var favoriteBrands: [String]
    var preferredSizes: [String: String]?
    var gender: String?
    var dateOfBirth: String?
    var location: String?
    var createdAt: String?
    var updatedAt: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decode(String.self, forKey: .email)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified)
        stylePreferences = try container.decodeIfPresent([String].self, forKey: .stylePreferences) ?? []
        favoriteBrands = try container.decodeIfPresent([String].self, forKey: .favoriteBrands) ?? []
        preferredSizes = try container.decodeIfPresent([String: String].self, forKey: .preferredSizes)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct UserUpdateRequest: Codable, Sendable {
    var firstName: String?
    var lastName: String?
    var bio: String?
    var gender: String?
    var dateOfBirth: String?
    var location: String?
    var stylePreferences: [String]?
    var favoriteBrands: [String]?
    var preferredSizes: [String: String]?
    /// Used by the calibration flow's "skip" path to mark onboarding done.
    var onboardingCompleted: Bool?
}

/// Body for `POST /users/me/onboarding` — the backend requires all three
/// collection fields (stylePreferences must be non-empty); gender is optional.
struct OnboardingRequest: Codable, Sendable {
    var stylePreferences: [String]
    var favoriteBrands: [String]
    var preferredSizes: [String: String]
    var gender: String?
}

struct AvatarUploadUrlResponse: Codable, Sendable {
    let signedUrl: String
    let publicUrl: String
    let path: String
}

struct AvatarUploadURLRequest: Encodable, Sendable {
    var fileExt: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fileExt, forKey: .fileExt)
    }

    private enum CodingKeys: String, CodingKey {
        case fileExt
    }
}

struct AvatarUrlUpdateRequest: Encodable, Sendable {
    let avatarUrl: String
}

struct DeviceTokenRequest: Codable, Sendable {
    let token: String
}
