import UIKit

/// Closet feel, haptics only (user-confirmed: no sounds). Generators are kept
/// alive and re-prepared so ticks land without first-use latency.
enum ClosetHaptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)

    /// A hanger snapped past center on the rail.
    static func railTick() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// The collections drawer opened or closed — a wooden thunk.
    static func drawerThunk() {
        medium.impactOccurred()
        medium.prepare()
    }

    /// An item landed in a collection (or on the mannequin).
    static func place() {
        soft.impactOccurred(intensity: 0.9)
        soft.prepare()
    }
}
