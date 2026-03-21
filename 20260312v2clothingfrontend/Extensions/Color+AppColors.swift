import SwiftUI

extension Color {
    /// Cobalt / electric blue for halftone base and large fills.
    static let appPopArtBlue = Color(red: 0.14, green: 0.28, blue: 0.72)

    /// Neon pink for accents, title bars, highlights.
    static let appNeonPink = Color(red: 1.0, green: 0.18, blue: 0.62)

    /// Flat fallback for previews (matches halftone base).
    static let appBackground = Color.appPopArtBlue

    /// Card / letterboxing fill (swipe cards, pop-art panels).
    static let cardBackground = Color.white

    static let appPrimaryText = Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)

    static let appSecondaryText = Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255).opacity(0.65)

    /// Text on halftone background (readable on blue/pink).
    static let appOnHalftonePrimary = Color.white

    static let appOnHalftoneSecondary = Color.white.opacity(0.82)

    /// Primary accent (CTA, tab bar, nav tint) — matches swipe card title band.
    static let appAccent = appNeonPink
}
