import SwiftUI

extension SwipeType {
    /// Stroke + offset extrusion while dragging on feed cards; history badges use the same hues.
    var swipeChromeColor: Color {
        switch self {
        case .LOVE: return Color(red: 0.18, green: 0.42, blue: 0.92)
        case .LIKE: return .green
        case .DISLIKE: return .red
        case .NEUTRAL: return .gray
        }
    }

    /// Center stamp label while dragging (dominant-axis preview).
    var swipeStampTitle: String {
        switch self {
        case .LOVE: return "I love it"
        case .LIKE: return "I like it"
        case .NEUTRAL: return "I don't mind it"
        case .DISLIKE: return "I hate it"
        }
    }
}
