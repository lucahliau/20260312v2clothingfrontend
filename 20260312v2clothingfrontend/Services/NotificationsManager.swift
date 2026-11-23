import Foundation
import UIKit
import UserNotifications

/// The app no longer schedules or registers for any notifications (the
/// twice-daily "come swipe" nudges and remote push are gone). What remains is
/// cleanup, so installs that scheduled them in the past stop receiving them.
enum NotificationsManager {
    /// Run on every launch: removes every pending local notification (the old
    /// repeating 9:00 / 14:00 nudges), clears delivered ones and the badge,
    /// and drops the APNS registration. Idempotent and cheap.
    static func cancelLegacyNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0)
        UIApplication.shared.unregisterForRemoteNotifications()
        UserDefaults.standard.removeObject(forKey: "lastUploadedApnsToken")
        UserDefaults.standard.removeObject(forKey: "friendsHotItemsNotifiedIds")
    }
}
