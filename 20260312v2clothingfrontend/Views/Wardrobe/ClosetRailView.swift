import QuartzCore
import SwiftUI

/// The Closet's hero: a flickable rail where hangers physically swing with the
/// scroll. Velocity (from scroll-geometry deltas) drives a spring-animated
/// rotation around each card's hook; when the rail settles, an underdamped
/// spring wobbles everything back to rest. A selection haptic ticks as each
/// hanger passes center.
struct ClosetRailView: View {
    let records: [SwipeRecord]
    var labelPlacement: ClosetLabelPlacement = .below
    var onTap: (SwipeRecord) -> Void

    static let railHeight: CGFloat = ClosetHangerCard.cardHeight + 12

    private static let cardSpacing: CGFloat = 14
    private static let railInset: CGFloat = 24
    private static let rodThickness: CGFloat = 9
    private static let maxSwingDegrees: Double = 11
    private static let velocityToDegrees: Double = 0.016

    @State private var swingAngle: Double = 0
    @State private var lastOffsetX: CGFloat = 0
    @State private var lastSampleTime: CFTimeInterval = 0
    @State private var settleTask: Task<Void, Never>?
    @State private var centeredIndex: Int?

    private struct RailGeometry: Equatable {
        var offsetX: CGFloat
        var viewportWidth: CGFloat
    }

    var body: some View {
        ZStack(alignment: .top) {
            PopArtRod()
                .frame(height: Self.rodThickness)
                .padding(.horizontal, 6)
                .padding(.top, ClosetHangerCard.hookCenterY - Self.rodThickness / 2 + 2)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Self.cardSpacing) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        ClosetHangerCard(
                            record: record,
                            isCentered: index == centeredIndex,
                            labelPlacement: labelPlacement,
                            onTap: { onTap(record) }
                        )
                        .rotationEffect(.degrees(swingAngle), anchor: ClosetHangerCard.hookAnchor)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.93, anchor: .top)
                                .opacity(phase.isIdentity ? 1.0 : 0.8)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Self.railInset)
                .padding(.top, ClosetHangerCard.hookCenterY)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .onScrollGeometryChange(for: RailGeometry.self) { geometry in
                RailGeometry(
                    offsetX: geometry.contentOffset.x,
                    viewportWidth: geometry.containerSize.width
                )
            } action: { _, new in
                handleScroll(new)
            }
        }
        .frame(height: Self.railHeight)
        .onAppear {
            if centeredIndex == nil, !records.isEmpty { centeredIndex = 0 }
        }
    }

    // MARK: - Physics

    private func handleScroll(_ geometry: RailGeometry) {
        let now = CACurrentMediaTime()
        defer {
            lastOffsetX = geometry.offsetX
            lastSampleTime = now
        }

        let dt = now - lastSampleTime
        if dt > 0, dt < 0.25 {
            let velocity = Double(geometry.offsetX - lastOffsetX) / dt
            let target = max(
                -Self.maxSwingDegrees,
                min(Self.maxSwingDegrees, -velocity * Self.velocityToDegrees)
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                swingAngle = target
            }
        }

        scheduleSettle()
        updateCenteredIndex(geometry)
    }

    /// When scroll events stop arriving, swing back to rest with a loose spring
    /// so the hangers visibly wobble before settling — the whole trick.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.32)) {
                swingAngle = 0
            }
        }
    }

    private func updateCenteredIndex(_ geometry: RailGeometry) {
        guard !records.isEmpty else { return }
        let cardStride = ClosetHangerCard.cardWidth + Self.cardSpacing
        let centerX = geometry.offsetX + geometry.viewportWidth / 2
        let raw = (centerX - Self.railInset - ClosetHangerCard.cardWidth / 2) / cardStride
        let index = max(0, min(records.count - 1, Int(raw.rounded())))
        if index != centeredIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                centeredIndex = index
            }
            ClosetHaptics.railTick()
        }
    }
}
