import SwiftUI

/// Shared pop-art card chrome (matches swipe cards): thick black stroke + offset extrusion.
enum PopArtCardStyle {
    static let cornerRadius: CGFloat = 20
    static let strokeWidth: CGFloat = 4
    static let shadowOffset: CGFloat = 8
}

extension View {
    /// White card with black outline and offset black “3D” layer behind.
    func popArtCardContainer() -> some View {
        background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius)
                    .stroke(Color.black, lineWidth: PopArtCardStyle.strokeWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius)
                    .fill(Color.black)
                    .offset(x: PopArtCardStyle.shadowOffset, y: PopArtCardStyle.shadowOffset)
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
