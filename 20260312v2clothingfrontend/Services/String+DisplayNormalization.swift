import Foundation

extension String {
    /// Fixes malformed `https:/host` / `http:/host` (single slash) sometimes returned by APIs.
    var normalizedAsHTTPURLString: String {
        if hasPrefix("https:/"), !hasPrefix("https://") {
            return "https://" + String(dropFirst(7))
        }
        if hasPrefix("http:/"), !hasPrefix("http://") {
            return "http://" + String(dropFirst(6))
        }
        return self
    }

    /// Title-style capitalization for product metadata shown in the UI (does not mutate stored/API values).
    var displayNormalizedTitle: String {
        guard !isEmpty else { return self }
        return localizedCapitalized
    }
}

extension Optional where Wrapped == String {
    var displayNormalizedTitle: String? {
        switch self {
        case nil: return nil
        case let s?: return s.isEmpty ? s : s.displayNormalizedTitle
        }
    }
}
