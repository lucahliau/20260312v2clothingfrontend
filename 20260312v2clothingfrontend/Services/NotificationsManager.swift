import Foundation
import UserNotifications

/// Local notifications: two daily "come swipe" nudges (9:00 and 14:00) plus
/// event alerts when 2+ friends like the same item (data from
/// `/social/friends/hot-items`, checked on app launch/foreground).
enum NotificationsManager {
    private static let morningId = "daily-nudge-morning"
    private static let afternoonId = "daily-nudge-afternoon"
    private static let notifiedHotItemsKey = "friendsHotItemsNotifiedIds"

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

    // MARK: - Friends hot items

    /// Fetches items that 2+ friends recently liked and fires one local
    /// notification per item (deduped across launches via UserDefaults).
    /// Silently no-ops when the endpoint is unavailable or permission denied.
    static func checkFriendsHotItems() async {
        guard await isAuthorized() else { return }
        guard let hot = try? await SocialService.fetchFriendsHotItems(), !hot.isEmpty else { return }

        var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedHotItemsKey) ?? [])
        let center = UNUserNotificationCenter.current()

        for entry in hot where entry.friendCount >= 2 && !notified.contains(entry.item.id) {
            notified.insert(entry.item.id)

            let content = UNMutableNotificationContent()
            content.title = "Your friends found something"
            content.body = "\(entry.friendCount) friends liked \(entry.item.name.displayNormalizedTitle). See what the fuss is about."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "friends-hot-\(entry.item.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            )
            try? await center.add(request)
        }

        // Cap the dedup list so it can't grow unbounded.
        UserDefaults.standard.set(Array(notified.suffix(300)), forKey: notifiedHotItemsKey)
    }
}
