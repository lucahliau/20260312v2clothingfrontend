import Foundation
import UIKit
import UserNotifications

/// Remote-push plumbing: requests an APNS token once notification permission
/// is granted and uploads it to the backend (`POST /users/me/device-tokens`).
/// The backend already pushes DMs, friend requests, and friend activity to
/// registered tokens — this is the missing client half.
enum PushRegistrationService {
    private static let lastUploadedKey = "lastUploadedApnsToken"

    /// Call after login / on launch once permission has been granted.
    /// Repeat calls are cheap: iOS re-fires the delegate with the same token
    /// and the upload is skipped when it matches the last one we sent.
    @MainActor
    static func registerIfAuthorized() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// AppDelegate hands the raw token here.
    static func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        Task {
            guard token != UserDefaults.standard.string(forKey: lastUploadedKey) else { return }
            do {
                try await UserService.registerDeviceToken(token)
                UserDefaults.standard.set(token, forKey: lastUploadedKey)
            } catch {
                // Not persisted as uploaded — the next registerIfAuthorized()
                // pass retries.
            }
        }
    }

    /// Best-effort: stop pushes to this device after logout. Must run while
    /// the session is still valid (the delete endpoint is authenticated).
    static func unregisterCurrentToken() async {
        guard let token = UserDefaults.standard.string(forKey: lastUploadedKey) else { return }
        try? await UserService.removeDeviceToken(token)
        UserDefaults.standard.removeObject(forKey: lastUploadedKey)
    }
}
