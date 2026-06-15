import SwiftUI

/// Shared card chrome (matches swipe cards): outline + offset extrusion.
/// Values forward to the active `Theme` so cards re-theme on Appearance switch;
/// the Pop Art preset keeps the original thick-black-stroke + 8pt extrusion look.
enum PopArtCardStyle {
    static var cornerRadius: CGFloat { Theme.current.cardCornerRadius }
    static var strokeWidth: CGFloat { Theme.current.cardStrokeWidth }
    static var shadowOffset: CGFloat { Theme.current.cardShadowOffset }
}

extension View {
    /// Card with themed outline and offset "3D" layer behind.
    func popArtCardContainer() -> some View {
        let theme = Theme.current
        return background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .stroke(theme.ink, lineWidth: theme.cardStrokeWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: theme.cardCornerRadius)
                    .fill(theme.shadowInk)
                    .offset(x: theme.cardShadowOffset, y: theme.cardShadowOffset)
            )
    }

    /// Opaque field fill on white auth cards (readable placeholder contrast vs `.quaternary`).
    func authFormFieldChrome() -> some View {
        padding()
            .background(Color(white: 0.95))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
    }
}
