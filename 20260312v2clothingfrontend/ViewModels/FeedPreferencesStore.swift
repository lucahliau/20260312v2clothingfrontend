import Foundation
import Observation

/// App-wide source of truth for feed tuning the user controls in Settings.
/// Currently just the "Discovery ↔ For You" personalization slider, persisted
/// to UserDefaults so it survives relaunch. `@Observable` so a Settings slider
/// bound to it updates reactively; `FeedViewModel` reads it when building feed
/// requests.
@MainActor
@Observable
final class FeedPreferencesStore {
    static let shared = FeedPreferencesStore()

    private static let defaultsKey = "feedPersonalization"

    /// Default mix (matches the backend's `PERSONALIZED_FRACTION`) so a user who
    /// never touches the slider gets today's behaviour.
    static let defaultPersonalization = 0.7

    /// 0 = pure Discovery (random/novelty), 1 = fully For You (recommendations).
    var personalization: Double {
        didSet {
            let clamped = min(1, max(0, personalization))
            if clamped != personalization {
                personalization = clamped // re-enters didSet, then persists below
                return
            }
            UserDefaults.standard.set(personalization, forKey: Self.defaultsKey)
        }
    }

    private init() {
        if UserDefaults.standard.object(forKey: Self.defaultsKey) != nil {
            personalization = UserDefaults.standard.double(forKey: Self.defaultsKey)
        } else {
            personalization = Self.defaultPersonalization
        }
    }
}
