import SwiftUI

/// Full-bleed app background. Pop Art draws the comic Ben-Day halftone (blue base
/// + cyan / neon pink / magenta dot grid); Refined draws a soft tonal wash from
/// paper to oat with only a faint trace of the dot motif. Which one is decided by
/// the active theme's `backgroundStyle`.
struct PopArtHalftoneBackground: View {
    var body: some View {
        // Read the theme here (during `body`) so the Canvas redraws on switch.
        let theme = Theme.current
        return GeometryReader { geo in
            Canvas { context, size in
                switch theme.backgroundStyle {
                case .halftone: Self.drawHalftone(context: &context, size: size, theme: theme)
                case .wash:     Self.drawWash(context: &context, size: size, theme: theme)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    /// Comic Ben-Day dots over a saturated base (the original Pop Art look).
    private static func drawHalftone(context: inout GraphicsContext, size: CGSize, theme: Theme) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.backgroundBase))

        let step: CGFloat = 10
        let dot: CGFloat = 3.5
        let palette: [Color] = [
            theme.halftoneCyan,
            theme.neonPink,
            theme.halftoneMagenta,
            Color.white,
            Color(red: 0.06, green: 0.06, blue: 0.1),
        ]

        var row = 0
        var y: CGFloat = step * 0.5
        while y < size.height + step {
            var col = 0
            var x: CGFloat = step * 0.5
            while x < size.width + step {
                let idx = (row + col) % palette.count
                let c = palette[idx]
                let rect = CGRect(x: x, y: y, width: dot, height: dot)
                context.fill(Path(ellipseIn: rect), with: .color(c.opacity(0.34)))
                x += step
                col += 1
            }
            y += step
            row += 1
        }
    }

    /// Calm vertical wash (paper → oat) with a sparse, very faint dot trace so the
    /// two themes still share visual DNA.
    private static func drawWash(context: inout GraphicsContext, size: CGSize, theme: Theme) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [theme.cardBackground, theme.backgroundBase]),
                startPoint: CGPoint(x: size.width * 0.5, y: 0),
                endPoint: CGPoint(x: size.width * 0.5, y: size.height)
            )
        )

        let step: CGFloat = 30
        let dot: CGFloat = 2.0
        var y: CGFloat = step * 0.5
        while y < size.height + step {
            var x: CGFloat = step * 0.5
            while x < size.width + step {
                let rect = CGRect(x: x, y: y, width: dot, height: dot)
                context.fill(Path(ellipseIn: rect), with: .color(theme.accent.opacity(0.05)))
                x += step
            }
            y += step
        }
    }
}
