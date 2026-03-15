import Foundation
import Observation

@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    init() {
        isAuthenticated = KeychainManager.read(key: KeychainManager.accessTokenKey) != nil
    }

    func checkSession() async {
        guard KeychainManager.read(key: KeychainManager.accessTokenKey) != nil else {
            isAuthenticated = false
            return
        }
        do {
            let _: User = try await NetworkManager.shared.request("/users/me")
            isAuthenticated = true
        } catch {
            KeychainManager.clearTokens()
            isAuthenticated = false
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await AuthService.login(email: email, password: password)
            storeTokens(response)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func register(email: String, username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await AuthService.register(email: email, username: username, password: password)
            storeTokens(response)
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func logout() async {
        try? await AuthService.logout()
        KeychainManager.clearTokens()
        isAuthenticated = false
    }

    private func storeTokens(_ response: AuthResponse) {
        KeychainManager.save(key: KeychainManager.accessTokenKey, data: response.accessToken)
        KeychainManager.save(key: KeychainManager.refreshTokenKey, data: response.refreshToken)
    }
}
