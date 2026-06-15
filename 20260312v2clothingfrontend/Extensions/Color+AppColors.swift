import SwiftUI

/// App colour tokens. These forward to the **active `Theme`**, so every call
/// site (`Color.appAccent`, `Color.cardBackground`, …) re-themes automatically
/// when the user switches Appearance — reading one inside a SwiftUI `body`
/// registers an Observation dependency on the theme store. The Pop Art preset's
/// values are identical to the constants these used to be, so nothing changes by
/// default. See `Theme.swift` for the values.
extension Color {
    /// Cobalt / electric blue base in Pop Art; warm oat wash in Refined.
    static var appPopArtBlue: Color { Theme.current.backgroundBase }

    /// Neon pink (Pop Art) / soft blush (Refined) — accent dots & highlights.
    static var appNeonPink: Color { Theme.current.neonPink }

    /// Full-bleed background base colour.
    static var appBackground: Color { Theme.current.backgroundBase }

    /// Card / panel / letterboxing fill.
    static var cardBackground: Color { Theme.current.cardBackground }

    static var appPrimaryText: Color { Theme.current.primaryText }

    static var appSecondaryText: Color { Theme.current.secondaryText }

    /// Text drawn over the app background (white on the dark halftone, dark ink
    /// on the light wash).
    static var appOnHalftonePrimary: Color { Theme.current.onBackgroundPrimary }

    static var appOnHalftoneSecondary: Color { Theme.current.onBackgroundSecondary }

    /// Primary accent (CTA, tab bar, nav tint).
    static var appAccent: Color { Theme.current.accent }

    /// Outline / extrusion ink — pure black in Pop Art, soft charcoal in Refined.
    /// Use this instead of a raw `Color.black` for card outlines and 3D shadows
    /// so they re-theme.
    static var appInk: Color { Theme.current.ink }

    /// Fill colour for the offset "3D" extrusion behind cards.
    static var appShadowInk: Color { Theme.current.shadowInk }
}
