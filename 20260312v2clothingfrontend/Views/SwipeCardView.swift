import SwiftUI

private let swipeThreshold: CGFloat = 80
private let swipeExitAnimationDuration: TimeInterval = 0.2
private let titleBandMinHeight: CGFloat = 56

struct SwipeCardView: View {
    let item: Item
    let onSwipe: (SwipeType) async -> Bool
    let onTap: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var imageLoadFinished = false

    private var hasImageURL: Bool {
        guard let pair = item.imageUrlPairs.first,
              let url = URL(string: pair.primary) else { return false }
        return !url.absoluteString.isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .bottom) {
                if !imageLoadFinished {
                    SwipeCardSkeletonView()
                }
                ZStack(alignment: .bottom) {
                    imageContent(size: size)
                    titleBand(width: size.width)
                }
                .opacity(imageLoadFinished ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            .background(Color.cardBackground)
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
            .rotation3DEffect(
                .degrees(rotationDegrees),
                axis: (x: 0, y: 1, z: 0.5),
                perspective: 0.5
            )
            .offset(x: dragOffset.width, y: dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let action = resolveAction(translation: value.translation)
                        if let action {
                            withAnimation(.easeOut(duration: swipeExitAnimationDuration)) {
                                dragOffset = exitOffset(for: action, in: size)
                            }
                            Task { @MainActor in
                                try? await Task.sleep(
                                    nanoseconds: UInt64(swipeExitAnimationDuration * 1_000_000_000)
                                )
                                _ = await onSwipe(action)
                            }
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            .onTapGesture {
                onTap()
            }
            .allowsHitTesting(imageLoadFinished)
        }
        .animation(.easeOut(duration: 0.2), value: imageLoadFinished)
        .onAppear {
            if !hasImageURL {
                imageLoadFinished = true
            }
        }
        .onChange(of: item.id) { _, _ in
            imageLoadFinished = !hasImageURL
        }
    }

    private var rotationDegrees: Double {
        let x = dragOffset.width
        let y = dragOffset.height
        let angle = atan2(y, x)
        return Double(angle) * 180 / .pi * 0.15
    }

    @ViewBuilder
    private func imageContent(size: CGSize) -> some View {
        if let pair = item.imageUrlPairs.first,
           let url = URL(string: pair.primary) {
            CachedAsyncImage(url: url, fallbackUrl: pair.fallback.flatMap { URL(string: $0) }, loadFinished: $imageLoadFinished)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Rectangle()
                .fill(.gray.opacity(0.3))
                .frame(width: size.width, height: size.height)
                .overlay { Text("No image").foregroundStyle(.secondary) }
        }
    }

    private func titleBand(width: CGFloat) -> some View {
        Text(item.name)
            .font(.appDisplay(size: 19))
            .foregroundStyle(Color.white)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minWidth: width, maxWidth: width, minHeight: titleBandMinHeight, alignment: .leading)
            .background(Color.appNeonPink)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: PopArtCardStyle.strokeWidth)
            }
    }

    private func resolveAction(translation: CGSize) -> SwipeType? {
        let dx = translation.width
        let dy = translation.height
        if abs(dx) > abs(dy) {
            if dx > swipeThreshold { return .LIKE }
            if dx < -swipeThreshold { return .DISLIKE }
        } else {
            if dy < -swipeThreshold { return .LOVE }
            if dy > swipeThreshold { return .NEUTRAL }
        }
        return nil
    }

    private func exitOffset(for action: SwipeType, in size: CGSize) -> CGSize {
        let margin: CGFloat = 100
        switch action {
        case .LOVE: return CGSize(width: 0, height: -size.height - margin)
        case .LIKE: return CGSize(width: size.width + margin, height: 0)
        case .DISLIKE: return CGSize(width: -size.width - margin, height: 0)
        case .NEUTRAL: return CGSize(width: 0, height: size.height + margin)
        }
    }
}
