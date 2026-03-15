import Foundation

enum HealthService {
    /// Returns server health and database connection status.
    static func checkHealth() async throws -> HealthResponse {
        try await NetworkManager.shared.request(
            "/health",
            authenticated: false
        )
    }
}
