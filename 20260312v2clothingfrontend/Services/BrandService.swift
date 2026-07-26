import Foundation

enum BrandService {
    /// Distinct brands with at least one active product; optional name filter.
    static func fetchBrands(q: String? = nil, limit: Int = 20) async throws -> [BrandInfo] {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(min(max(limit, 1), APIQueryLimits.maxBrands))")]
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
        let capped = min(max(limit, 1), APIQueryLimits.maxExploreBrands)
        let response: BrandListResponse = try await NetworkManager.shared.request(
            "/brands/explore",
            queryItems: [URLQueryItem(name: "limit", value: "\(capped)")]
        )
        return response.brands
    }

    /// Server-composed featured rail: brand counts and four collage items in
    /// one cached request.
    static func fetchFeaturedBrands(limit: Int = 5) async throws -> [FeaturedBrandInfo] {
        let capped = min(max(limit, 1), 40)
        let response: FeaturedBrandsResponse = try await NetworkManager.shared.request(
            "/brands/featured",
            queryItems: [URLQueryItem(name: "limit", value: "\(capped)")]
        )
        return response.brands
    }

    // MARK: - Saved brands

    /// The caller's saved brands, with live product counts.
    static func fetchFavoriteBrands() async throws -> [BrandInfo] {
        let response: BrandListResponse = try await NetworkManager.shared.request("/brands/favorites")
        return response.brands
    }

    /// Saves or unsaves a brand; returns the updated saved-brand names.
    @discardableResult
    static func setFavoriteBrand(_ brand: String, favorite: Bool) async throws -> [String] {
        let body = SetFavoriteBrandRequest(brand: brand, favorite: favorite)
        let response: FavoriteBrandsUpdateResponse = try await NetworkManager.shared.request(
            "/brands/favorites",
            method: "PUT",
            body: body
        )
        return response.favoriteBrands
    }
}
