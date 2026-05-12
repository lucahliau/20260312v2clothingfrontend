import Foundation
import Security

enum KeychainManager {
    static let accessTokenKey = "accessToken"
    static let refreshTokenKey = "refreshToken"
    static let deviceIdKey = "deviceId"

    /// Returns the stable per-device identifier, generating + persisting one on
    /// first call. Stored in Keychain (no iCloud sync) so it survives reinstalls
    /// but is unique per physical device — the server keys per-device sessions
    /// off this.
    static func deviceId() -> String {
        if let existing = read(key: deviceIdKey), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString
        save(key: deviceIdKey, data: new)
        return new
    }

    static func save(key: String, data: String) {
        guard let data = data.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearTokens() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
    }
}
