import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(statusCode: Int, message: String?)
    case unauthorized
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL."
        case .noData: return "No data received."
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        case .serverError(let code, let msg): return "Server error \(code): \(msg ?? "Unknown")"
        case .unauthorized: return "Session expired. Please log in again."
        case .unknown(let err): return err.localizedDescription
        }
    }
}

final class NetworkManager {
    static let shared = NetworkManager()

    let baseURL = "https://20260311-clothes-backend-production.up.railway.app"
    private let session = URLSession.shared

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
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
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
                throw NetworkError.serverError(statusCode: http.statusCode, message: apiError.error.message)
            }
            throw NetworkError.serverError(statusCode: http.statusCode, message: nil)
        }
    }

    // MARK: - Token refresh

    private func refreshTokens() async throws {
        guard let refreshToken = KeychainManager.read(key: KeychainManager.refreshTokenKey) else {
            KeychainManager.clearTokens()
            throw NetworkError.unauthorized
        }

        let body = RefreshRequest(refreshToken: refreshToken)
        let request = try buildRequest("/auth/refresh", method: "POST", body: body, queryItems: nil, authenticated: false)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            KeychainManager.clearTokens()
            throw NetworkError.unauthorized
        }

        let tokens = try decoder.decode(TokenResponse.self, from: data)
        KeychainManager.save(key: KeychainManager.accessTokenKey, data: tokens.accessToken)
        KeychainManager.save(key: KeychainManager.refreshTokenKey, data: tokens.refreshToken)
    }
}
