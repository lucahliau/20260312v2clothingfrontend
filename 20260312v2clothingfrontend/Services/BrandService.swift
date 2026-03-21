import Foundation

enum BrandService {
    /// Distinct brands with at least one active product; optional name filter.
    static func fetchBrands(q: String? = nil, limit: Int = 20) async throws -> [BrandInfo] {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(min(max(limit, 1), 100))")]
        if let q, !q.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: q))
        }
        let response: BrandListResponse = try await NetworkManager.shared.request(
            "/brands",
            queryItems: queryItems
        )
        return response.brands
    }

    /// Random sample of brands for explore UI.
    static func fetchExploreBrands(limit: Int = 12) async throws -> [BrandInfo] {
        let capped = min(max(limit, 1), 50)
        let response: BrandListResponse = try await NetworkManager.shared.request(
            "/brands/explore",
            queryItems: [URLQueryItem(name: "limit", value: "\(capped)")]
        )
        return response.brands
    }
}
