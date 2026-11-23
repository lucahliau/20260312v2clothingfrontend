import Foundation
import UserNotifications

/// Local notifications: two daily "come swipe" nudges (9:00 and 14:00).
enum NotificationsManager {
    private static let morningId = "daily-nudge-morning"
    private static let afternoonId = "daily-nudge-afternoon"

    /// Call once the user is authenticated: asks permission on first run,
    /// then (re)schedules the repeating daily nudges.
    static func setupAfterLogin() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        guard await isAuthorized() else { return }
        scheduleDailyNudges()
        // Remote pushes (DMs, friend requests) ride the same permission.
        await PushRegistrationService.registerIfAuthorized()
    }

    private static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    // MARK: - Daily nudges

    /// Re-adding with the same identifier replaces the pending request, so
    /// calling this on every launch is idempotent.
    private static func scheduleDailyNudges() {
        scheduleDaily(
            id: morningId,
            hour: 9,
            title: "Fresh fits this morning",
            body: "New pieces landed in your Feed overnight. Come swipe."
        )
        scheduleDaily(
            id: afternoonId,
            hour: 14,
            title: "Style break",
            body: "Take a minute — see what's new in your Feed."
        )
    }

    private static func scheduleDaily(id: String, hour: Int, title: String, body: String) {
        var date = DateComponents()
        date.hour = hour
        date.minute = 0

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    /// Clear everything on logout so a signed-out device stops nudging.
    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
