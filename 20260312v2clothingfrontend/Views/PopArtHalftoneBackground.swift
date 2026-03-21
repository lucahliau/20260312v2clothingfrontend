import SwiftUI

/// Comic Ben-Day style halftone: blue base + cyan / neon pink / magenta dot grid.
struct PopArtHalftoneBackground: View {
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let base = Color.appPopArtBlue
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

                let step: CGFloat = 10
                let dot: CGFloat = 3.5
                let palette: [Color] = [
                    Color(red: 0.2, green: 0.95, blue: 1.0),
                    Color.appNeonPink,
                    Color(red: 0.85, green: 0.15, blue: 0.95),
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
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}
