import SwiftUI

/// Closet furniture — comic-book rails, shelves and tags that match the app's
/// card language. Colours and chrome forward to the active `Theme`, so the
/// closet shifts from bold-black-and-neon (Pop Art) to soft-ink-and-blush
/// (Refined) along with everything else. No wood, no image assets.

/// The closet's clothes rail: a bold ink bar with neon end caps.
struct PopArtRod: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(Theme.current.ink)
            HStack {
                pinkCap
                Spacer()
                pinkCap
            }
        }
    }

    private var pinkCap: some View {
        Capsule()
            .fill(Color.appNeonPink)
            .overlay(Capsule().strokeBorder(Theme.current.ink, lineWidth: 2))
            .frame(width: 16)
            .padding(.vertical, -2)
    }
}

/// A comic-style sticker tag: card-coloured panel, themed outline, offset
/// extrusion, hung at a slight (theme-driven) angle.
struct PopArtTag<Content: View>: View {
    /// Defaults to the theme's playful tilt; pass an explicit value to override.
    var rotation: Double = Theme.current.tagRotation
    @ViewBuilder var content: Content

    var body: some View {
        let theme = Theme.current
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: theme.tagCornerRadius, style: .continuous)
                    .fill(theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: theme.tagCornerRadius, style: .continuous)
                    .stroke(theme.ink, lineWidth: theme.tagStrokeWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: theme.tagCornerRadius, style: .continuous)
                    .fill(theme.shadowInk)
                    .offset(x: theme.tagShadowOffset, y: theme.tagShadowOffset)
            )
            .rotationEffect(.degrees(rotation))
    }
}

/// A shelf plank for bags and shoes: flat ink slab with a neon top edge.
struct PopArtShelfPlank: View {
    var cornerRadius: CGFloat = 4

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.current.ink)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.appNeonPink)
                .frame(height: 3)
                .padding(.horizontal, 3)
                .padding(.top, 2)
        }
    }
}
