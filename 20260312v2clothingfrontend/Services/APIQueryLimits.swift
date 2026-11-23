import Foundation

/// Backend caps for `limit` query parameters (`GET /brands`, `GET /brands/explore`, `GET /items`).
enum APIQueryLimits {
    static let maxBrands = 1000
    static let maxExploreBrands = 100
    static let maxItemsPerPage = 200
}
