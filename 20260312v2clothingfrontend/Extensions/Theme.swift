import SwiftUI
import UIKit
import Observation

/// The two interchangeable visual identities the user picks in Settings →
/// Appearance. Both themes share the SAME component shapes (outlined cards,
/// offset "3D" extrusion, sticker tags, slight tilts) — the `Theme` values are
/// what make one loud-and-comic and the other calm-and-boutique.
enum ThemeStyle: String, CaseIterable, Identifiable {
    case popArt
    case refined

    var id: String { rawValue }

    /// Label shown in the Appearance picker.
    var displayName: String {
        switch self {
        case .popArt:  return "Pop Art"
        case .refined: return "Refined"
        }
    }

    /// One-line description under the picker label.
    var tagline: String {
        switch self {
        case .popArt:  return "Bold comic-book colour"
        case .refined: return "Calm boutique minimal"
        }
    }
}

/// How the full-bleed app background is drawn for a theme.
enum ThemeBackgroundStyle {
    /// Saturated base under a Ben-Day comic dot grid (the original look).
    case halftone
    /// Soft tonal wash with only a whisper of the dot motif.
    case wash
}

/// A complete visual identity: palette + the structural "3D / playful" knobs
/// the card language is built from. The pop-art preset's values are deliberately
/// byte-identical to the constants the app shipped with, so selecting Pop Art is
/// pixel-for-pixel the original UI.
struct Theme {
    let style: ThemeStyle

    // MARK: Palette
    /// CTA / tab + nav tint / highlights.
    let accent: Color
    /// Halftone / wash base colour.
    let backgroundBase: Color
    /// Accent dots + minor highlights.
    let neonPink: Color
    /// Halftone dot palette (only fully visible in `.halftone`).
    let halftoneCyan: Color
    let halftoneMagenta: Color
    /// Text on light cards.
    let primaryText: Color
    let secondaryText: Color
    /// Text drawn directly over the app background.
    let onBackgroundPrimary: Color
    let onBackgroundSecondary: Color
    /// Card / panel fill (was a raw `Color.white`).
    let cardBackground: Color
    /// Outline + extrusion colour (was a raw `Color.black`).
    let ink: Color
    /// 3D extrusion fill behind cards (usually `ink`, optionally softened).
    let shadowInk: Color

    // MARK: Card chrome
    let cardStrokeWidth: CGFloat
    let cardCornerRadius: CGFloat
    let cardShadowOffset: CGFloat

    // MARK: Title bar
    /// Hard offset of the title's drop shadow.
    let titleShadowOffset: CGFloat

    // MARK: Sticker-tag chrome
    let tagStrokeWidth: CGFloat
    let tagShadowOffset: CGFloat
    let tagCornerRadius: CGFloat
    let tagRotation: Double

    // MARK: Background treatment
    let backgroundStyle: ThemeBackgroundStyle
}

// MARK: - Presets

extension Theme {
    /// The original comic / pop-art identity. **These values match the previous
    /// hardcoded constants exactly — do not "tidy" them or the default look drifts.**
    static let popArt = Theme(
        style: .popArt,
        accent: Color(red: 1.0, green: 0.18, blue: 0.62),
        backgroundBase: Color(red: 0.14, green: 0.28, blue: 0.72),
        neonPink: Color(red: 1.0, green: 0.18, blue: 0.62),
        halftoneCyan: Color(red: 0.2, green: 0.95, blue: 1.0),
        halftoneMagenta: Color(red: 0.85, green: 0.15, blue: 0.95),
        primaryText: Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255),
        secondaryText: Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255).opacity(0.65),
        onBackgroundPrimary: Color.white,
        onBackgroundSecondary: Color.white.opacity(0.82),
        cardBackground: Color.white,
        ink: Color.black,
        shadowInk: Color.black,
        cardStrokeWidth: 4,
        cardCornerRadius: 20,
        cardShadowOffset: 8,
        titleShadowOffset: 2.5,
        tagStrokeWidth: 2.5,
        tagShadowOffset: 3,
        tagCornerRadius: 9,
        tagRotation: -2.5,
        backgroundStyle: .halftone
    )

    /// A calmer, boutique-leaning identity for a more refined / premium audience.
    /// Keeps the outlined-card + offset-extrusion "3D" language and the dot motif,
    /// but in warm paper tones with a dusty-rose accent, softer charcoal ink,
    /// thinner strokes and gentler tilts. A starting point — tune freely.
    static let refined = Theme(
        style: .refined,
        accent: Color(red: 0.78, green: 0.34, blue: 0.42),
        backgroundBase: Color(red: 0.95, green: 0.93, blue: 0.90),
        neonPink: Color(red: 0.85, green: 0.62, blue: 0.66),
        halftoneCyan: Color(red: 0.74, green: 0.78, blue: 0.79),
        halftoneMagenta: Color(red: 0.82, green: 0.66, blue: 0.69),
        primaryText: Color(red: 0.15, green: 0.14, blue: 0.16),
        secondaryText: Color(red: 0.15, green: 0.14, blue: 0.16).opacity(0.55),
        onBackgroundPrimary: Color(red: 0.17, green: 0.15, blue: 0.17),
        onBackgroundSecondary: Color(red: 0.17, green: 0.15, blue: 0.17).opacity(0.62),
        cardBackground: Color(red: 0.99, green: 0.98, blue: 0.96),
        ink: Color(red: 0.18, green: 0.16, blue: 0.18),
        shadowInk: Color(red: 0.18, green: 0.16, blue: 0.18).opacity(0.5),
        cardStrokeWidth: 2.5,
        cardCornerRadius: 18,
        cardShadowOffset: 5,
        titleShadowOffset: 1.5,
        tagStrokeWidth: 1.5,
        tagShadowOffset: 2,
        tagCornerRadius: 11,
        tagRotation: -1,
        backgroundStyle: .wash
    )

    static func preset(for style: ThemeStyle) -> Theme {
        switch style {
        case .popArt:  return .popArt
        case .refined: return .refined
        }
    }

    /// The currently active theme. Reading this inside a SwiftUI `body` registers
    /// an Observation dependency on `ThemeStore.shared.style`, so views re-render
    /// the instant the user switches — no environment plumbing required.
    static var current: Theme { ThemeStore.shared.active }
}

// MARK: - Store

/// App-wide source of truth for the selected theme. A single `@Observable` so
/// every token (`Color.appAccent`, …) and primitive that reads `Theme.current`
/// during `body` re-renders reactively when `style` flips.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private static let defaultsKey = "uiThemeStyle"

    var style: ThemeStyle {
        didSet {
            guard style != oldValue else { return }
            UserDefaults.standard.set(style.rawValue, forKey: Self.defaultsKey)
            // Re-skin the UIKit nav/tab proxies so screens pushed after the switch
            // pick up the new title colour/tint. (Live SwiftUI surfaces update via
            // their token reads + RootView's `.tint`.)
            active.applyUIKitAppearance()
        }
    }

    /// The resolved theme for the current `style`.
    var active: Theme { Theme.preset(for: style) }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey)
        style = ThemeStyle(rawValue: raw ?? ThemeStyle.popArt.rawValue) ?? .popArt
    }
}

// MARK: - UIKit appearance

extension Theme {
    /// Configures the global navigation- and tab-bar appearance proxies for this
    /// theme. Called once at launch and again whenever the theme changes. Fonts
    /// stay Montserrat in both themes, so only colours differ here.
    func applyUIKitAppearance() {
        let titleLarge = UIFont.appDisplay(size: 34)
        let titleInline = UIFont.appDisplay(size: 17)
        let titleColor = UIColor(onBackgroundPrimary)

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.font: titleLarge, .foregroundColor: titleColor]
        nav.titleTextAttributes = [.font: titleInline, .foregroundColor: titleColor]

        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactScrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(accent)

        let tabFont = UIFont.appDisplay(size: 10)
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [
            .font: tabFont,
            .foregroundColor: UIColor(secondaryText),
        ]
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [
            .font: tabFont,
            .foregroundColor: UIColor(accent),
        ]

        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = UIColor(accent)
    }
}
