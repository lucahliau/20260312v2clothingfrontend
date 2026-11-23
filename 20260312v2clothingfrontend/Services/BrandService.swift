import Foundation

enum BrandService {
    /// Distinct brands with at least one active product; optional name filter.
    /// `minProducts` hides brands with fewer active products (server-side).
    /// The server returns them sorted A–Z.
    static func fetchBrands(q: String? = nil, limit: Int = 20, minProducts: Int? = nil) async throws -> [BrandInfo] {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(min(max(limit, 1), APIQueryLimits.maxBrands))")]
        if let q, !q.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: q))
        }
        if let minProducts, minProducts > 1 {
            queryItems.append(URLQueryItem(name: "minProducts", value: "\(minProducts)"))
        }
        let response: BrandListResponse = try await NetworkManager.shared.request(
            "/brands",
            queryItems: queryItems
        )
        return response.brands
    }

    /// Every brand in the catalog (A–Z) for the "All brands" list.
    static func fetchAllBrands(minProducts: Int? = nil) async throws -> [BrandInfo] {
        try await fetchBrands(limit: APIQueryLimits.maxBrands, minProducts: minProducts)
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
