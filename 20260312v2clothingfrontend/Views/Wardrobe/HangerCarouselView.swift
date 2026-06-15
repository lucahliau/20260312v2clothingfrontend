import SwiftUI

struct HangerCarouselView: View {
    let records: [SwipeRecord]
    var onTap: (SwipeRecord) -> Void

    private static let cardSpacing: CGFloat = 10
    private static let railInset: CGFloat = 20

    var body: some View {
        ZStack(alignment: .top) {
            rod
                .padding(.top, HangerCardView.rodCenterY - HangerCardView.rodThickness / 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Self.cardSpacing) {
                    ForEach(records) { record in
                        HangerCardView(record: record, onTap: { onTap(record) })
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.9)
                                    .rotation3DEffect(
                                        .degrees(phase.value * -16),
                                        axis: (x: 0, y: 1, z: 0),
                                        perspective: 0.7
                                    )
                                    .opacity(phase.isIdentity ? 1.0 : 0.78)
                            }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Self.railInset)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private var rod: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.white.opacity(0.85),
                        Color.white.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: HangerCardView.rodThickness)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            .padding(.horizontal, 4)
    }
}
