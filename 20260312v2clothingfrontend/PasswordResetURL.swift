import Foundation

enum PasswordResetURL {
    private static let tokenQueryNames = ["token", "reset_token", "resetToken"]

    /// True when the URL path targets the password reset screen (with or without a token).
    static func looksLikePasswordResetURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
        return isResetPasswordPath(components.path)
    }

    /// Matches backend reset links: `.../reset-password?token=...` (also `reset_token`, `resetToken`, fragment `#token=...`).
    static func token(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }
        guard isResetPasswordPath(components.path) else { return nil }

        if let t = tokenFromQueryItems(components.queryItems) {
            return t
        }
        if let fragment = components.fragment, !fragment.isEmpty {
            let fragmentComponents = URLComponents(string: "https://placeholder.invalid/?\(fragment)")
            if let t = tokenFromQueryItems(fragmentComponents?.queryItems) {
                return t
            }
            // Some links use fragment without `&`: `#token=...` only
            if let t = tokenFromRawFragment(fragment) {
                return t
            }
        }
        return nil
    }

    private static func isResetPasswordPath(_ path: String) -> Bool {
        if path == "/reset-password" || path == "/reset-password/" { return true }
        return path.hasSuffix("/reset-password") || path.hasSuffix("/reset-password/")
    }

    private static func tokenFromQueryItems(_ items: [URLQueryItem]?) -> String? {
        guard let items else { return nil }
        for name in tokenQueryNames {
            guard let raw = items.first(where: { $0.name == name })?.value else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return normalizeTokenString(trimmed)
        }
        return nil
    }

    /// Handles fragments that are not valid query strings (e.g. malformed encoding).
    private static func tokenFromRawFragment(_ fragment: String) -> String? {
        for name in tokenQueryNames {
            let prefix = "\(name)="
            guard fragment.hasPrefix(prefix) else { continue }
            let rest = String(fragment.dropFirst(prefix.count))
            guard !rest.isEmpty else { continue }
            return normalizeTokenString(rest)
        }
        return nil
    }

    private static func normalizeTokenString(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }
}
