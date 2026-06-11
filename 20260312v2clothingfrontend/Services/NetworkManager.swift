import Foundation

extension Notification.Name {
    /// Posted exactly once per real session death: the server rejected our
    /// refresh token. AuthViewModel listens and flips the auth gate.
    static let authSessionExpired = Notification.Name("clothedd.authSessionExpired")
}

enum NetworkError: LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(statusCode: Int, message: String?, code: String?)
    /// Real session death: the server told us our refresh token is invalid.
    /// Clear tokens and force re-login.
    case unauthorized
    /// Refresh failed for a non-auth reason (timeout, 5xx, DNS, etc). Tokens
    /// are intentionally left alone — the user is *not* logged out.
    case transient(underlying: Error?)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .noData: return "The server returned no data. Try again, or check that the API response matches the app."
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        case .serverError(let status, let msg, _): return "Server error \(status): \(msg ?? "Unknown")"
        case .unauthorized: return "Session expired. Please log in again."
        case .transient: return "Couldn't reach the server. Check your connection and try again."
        case .unknown(let err): return err.localizedDescription
        }
    }
}

/// Serializes `/auth/refresh` calls so a burst of concurrent 401s collapses
/// into a single network round-trip. Every caller awaits the same in-flight
/// task; when it completes they all get the new access token (or the same
/// error) and can retry their original request.
actor TokenRefresher {
    private var inFlight: Task<Void, Error>?

    /// Refreshes tokens if needed. The work is wrapped in a single `Task` so
    /// concurrent callers share its result. The closure is responsible for
    /// persisting the new tokens to Keychain before returning.
    func refresh(_ work: @Sendable @escaping () async throws -> Void) async throws {
        if let existing = inFlight {
            try await existing.value
            return
        }
        let task = Task<Void, Error> {
            try await work()
        }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }
}

final class NetworkManager {
    static let shared = NetworkManager()

    let baseURL = "https://20260311-clothes-backend-production.up.railway.app"
    private let session = URLSession.shared
    private let tokenRefresher = TokenRefresher()

    private init() {}

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }

    // MARK: - Public request (with automatic 401 retry)

    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        do {
            return try await performRequest(endpoint, method: method, body: body, queryItems: queryItems, authenticated: authenticated)
        } catch NetworkError.unauthorized where authenticated {
            try await refreshTokens()
            return try await performRequest(endpoint, method: method, body: body, queryItems: queryItems, authenticated: authenticated)
        }
    }

    func requestVoid(
        _ endpoint: String,
        method: String = "POST",
        body: (any Encodable & Sendable)? = nil,
        authenticated: Bool = true
    ) async throws {
        do {
            try await performRequestVoid(endpoint, method: method, body: body, authenticated: authenticated)
        } catch NetworkError.unauthorized where authenticated {
            try await refreshTokens()
            try await performRequestVoid(endpoint, method: method, body: body, authenticated: authenticated)
        }
    }

    /// PUT binary data to a signed URL (e.g. Supabase). No `Authorization` header.
    func putBytes(_ data: Data, to urlString: String, contentType: String) async throws {
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let (body, response) = try await session.data(for: request)
        try validateSignedUploadResponse(response, data: body)
    }

    // MARK: - Private helpers

    private func performRequest<T: Decodable>(
        _ endpoint: String,
        method: String,
        body: (any Encodable & Sendable)?,
        queryItems: [URLQueryItem]?,
        authenticated: Bool
    ) async throws -> T {
        let request = try buildRequest(endpoint, method: method, body: body, queryItems: queryItems, authenticated: authenticated)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.isEmpty {
            throw NetworkError.noData
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            let snippet = String(data: data.prefix(900), encoding: .utf8) ?? "<non-utf8 body>"
            print("[NetworkManager] Decode failed \(method) \(endpoint): \(error)\nBody prefix: \(snippet)")
            #endif
            throw NetworkError.decodingError(error)
        }
    }

    private func performRequestVoid(
        _ endpoint: String,
        method: String,
        body: (any Encodable & Sendable)?,
        authenticated: Bool
    ) async throws {
        let request = try buildRequest(endpoint, method: method, body: body, queryItems: nil, authenticated: authenticated)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    private func buildRequest(
        _ endpoint: String,
        method: String,
        body: (any Encodable & Sendable)?,
        queryItems: [URLQueryItem]?,
        authenticated: Bool
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = KeychainManager.read(key: KeychainManager.accessTokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300:
            return
        case 401:
            throw NetworkError.unauthorized
        default:
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw NetworkError.serverError(
                    statusCode: http.statusCode,
                    message: apiError.error.message,
                    code: apiError.error.code
                )
            }
            throw NetworkError.serverError(statusCode: http.statusCode, message: nil, code: nil)
        }
    }

    private func validateSignedUploadResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw NetworkError.serverError(statusCode: http.statusCode, message: message, code: nil)
        }
    }

    // MARK: - Token refresh

    /// Entry point used by `request` / `requestVoid` on a 401. Funnels every
    /// concurrent refresh through the actor so we make exactly one network
    /// call regardless of how many callers are waiting.
    private func refreshTokens() async throws {
        try await tokenRefresher.refresh { [weak self] in
            try await self?.doRefresh()
        }
    }

    private func doRefresh() async throws {
        guard let refreshToken = KeychainManager.read(key: KeychainManager.refreshTokenKey) else {
            // No refresh token at all — definitely a logged-out state.
            KeychainManager.clearTokens()
            throw NetworkError.unauthorized
        }

        let body = RefreshRequest(refreshToken: refreshToken, deviceId: KeychainManager.deviceId())
        let request = try buildRequest("/auth/refresh", method: "POST", body: body, queryItems: nil, authenticated: false)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Network failure (timeout, DNS, offline). The tokens are still
            // potentially valid — never log the user out for connectivity.
            throw NetworkError.transient(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.transient(underlying: nil)
        }
        if http.statusCode == 401 {
            // Server explicitly rejected the refresh token. Real session death.
            KeychainManager.clearTokens()
            NotificationCenter.default.post(name: .authSessionExpired, object: nil)
            throw NetworkError.unauthorized
        }
        if !(200..<300).contains(http.statusCode) {
            // 5xx, 429, etc. — transient; do not touch Keychain.
            throw NetworkError.transient(underlying: nil)
        }

        let tokens = try decoder.decode(TokenResponse.self, from: data)
        KeychainManager.save(key: KeychainManager.accessTokenKey, data: tokens.accessToken)
        KeychainManager.save(key: KeychainManager.refreshTokenKey, data: tokens.refreshToken)
    }
}
