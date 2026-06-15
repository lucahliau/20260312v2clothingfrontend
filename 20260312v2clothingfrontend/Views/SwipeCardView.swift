import SwiftUI

private let swipeThreshold: CGFloat = 80
private let swipePreviewDeadZone: CGFloat = 10
private let swipeExitAnimationDuration: TimeInterval = 0.2
private let titleBandMinHeight: CGFloat = 56

struct SwipeCardView: View {
    let item: Item
    let onSwipe: (SwipeType) async -> Bool
    let onTap: () -> Void
    /// Feed only: drop the card when primary+fallback end in HTTP 404.
    var onUnrecoverableImage404: (() -> Void)? = nil
    /// Optional match metadata; when present a small badge renders in the
    /// top-right corner. `nil` for non-feed callers (e.g. swipe history).
    var match: FeedMatch? = nil
    /// Invoked when the user taps the match badge (caller presents an
    /// explainer sheet). When `nil` the badge is shown but non-tappable.
    var onMatchTap: (() -> Void)? = nil

    @State private var dragOffset: CGSize = .zero
    @State private var imageLoadFinished: Bool
    /// True once a swipe action has been committed and the card is flying off.
    /// Blocks a second drag during the ~0.4s exit window from double-firing a
    /// swipe (which would skip a card).
    @State private var isExiting = false

    init(
        item: Item,
        onSwipe: @escaping (SwipeType) async -> Bool,
        onTap: @escaping () -> Void,
        onUnrecoverableImage404: (() -> Void)? = nil,
        match: FeedMatch? = nil,
        onMatchTap: (() -> Void)? = nil
    ) {
        self.item = item
        self.onSwipe = onSwipe
        self.onTap = onTap
        self.onUnrecoverableImage404 = onUnrecoverableImage404
        self.match = match
        self.onMatchTap = onMatchTap
        // Seed the load gate from the synchronous image cache. When the image was
        // already prefetched (the common case with the feed's look-ahead), the
        // card renders instantly — no skeleton, no fade — which removes the
        // "flash" as the next card became current. A genuinely-uncached image
        // still starts false and fades in once loaded.
        _imageLoadFinished = State(initialValue: Self.imageReadySynchronously(for: item))
    }

    /// True when the card can show immediately: no image to load, or its primary
    /// image is already in the in-memory cache.
    private static func imageReadySynchronously(for item: Item) -> Bool {
        guard let pair = item.imageUrlPairs.first,
              let url = URL(string: pair.primary),
              !url.absoluteString.isEmpty else {
            return true
        }
        return ImageCacheService.shared.image(for: url) != nil
    }

    private var hasImageURL: Bool {
        guard let pair = item.imageUrlPairs.first,
              let url = URL(string: pair.primary) else { return false }
        return !url.absoluteString.isEmpty
    }

    private var swipeChromeColor: Color {
        if let preview = dominantSwipePreview(translation: dragOffset) {
            return preview.swipeChromeColor
        }
        return .black
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
                .overlay(alignment: .topTrailing) {
                    if let badge = MatchBadgeStyle.from(match: match), imageLoadFinished {
                        matchBadge(badge)
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                    }
                }
                .overlay {
                    if let preview = dominantSwipePreview(translation: dragOffset), imageLoadFinished {
                        previewStamp(for: preview, translation: dragOffset)
                    }
                }
                .opacity(imageLoadFinished ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius)
                    .stroke(swipeChromeColor, lineWidth: PopArtCardStyle.strokeWidth)
            )
            .background(
                RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius)
                    .fill(swipeChromeColor)
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
                        guard !isExiting else { return }
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard !isExiting else { return }
                        let action = resolveAction(translation: value.translation)
                        if let action {
                            isExiting = true
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
            .allowsHitTesting(imageLoadFinished && !isExiting)
        }
        .animation(.easeOut(duration: 0.2), value: imageLoadFinished)
        .onAppear {
            if !hasImageURL {
                imageLoadFinished = true
            }
        }
        .onChange(of: item.id) { _, _ in
            // Defensive: feed cards now keep a stable identity per item (the deck
            // window promotes cards in place rather than rebuilding them), so this
            // only fires for callers that reuse a card instance for a new item
            // (e.g. swipe history). Re-seed the load gate from cache and clear the
            // exit guard so the reused instance is interactive again.
            imageLoadFinished = Self.imageReadySynchronously(for: item)
            isExiting = false
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
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                logContext: "feed",
                loadFinished: $imageLoadFinished,
                // SwipeCardView's init/onChange is the single writer that drives
                // the gate false; let CachedAsyncImage only ever drive it true
                // (on load completion). Prevents a one-frame fade race where a
                // freshly-mounted task resets a cache-hit card back to loading.
                resetsLoadingBinding: false,
                onUnrecoverableHTTP404: onUnrecoverableImage404
            )
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

    /// Same dominant-axis rule as `resolveAction`, but activates after a small dead zone (preview only).
    private func dominantSwipePreview(translation: CGSize) -> SwipeType? {
        let dx = translation.width
        let dy = translation.height
        let dead = swipePreviewDeadZone
        if abs(dx) <= dead && abs(dy) <= dead { return nil }

        if abs(dx) > abs(dy) {
            guard abs(dx) > dead else { return nil }
            return dx > 0 ? .LIKE : .DISLIKE
        } else {
            guard abs(dy) > dead else { return nil }
            return dy < 0 ? .LOVE : .NEUTRAL
        }
    }

    private func previewIntensity(translation: CGSize) -> CGFloat {
        let dx = translation.width
        let dy = translation.height
        let dead = swipePreviewDeadZone
        if abs(dx) <= dead && abs(dy) <= dead { return 0 }
        let dominant: CGFloat = abs(dx) > abs(dy) ? abs(dx) : abs(dy)
        return min(dominant / swipeThreshold, 1)
    }

    @ViewBuilder
    private func previewStamp(for type: SwipeType, translation: CGSize) -> some View {
        let t = previewIntensity(translation: translation)
        Text(type.swipeStampTitle)
            .font(.appDisplay(size: 19))
            .fontWeight(.regular)
            .foregroundStyle(type.swipeChromeColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Color.white.opacity(0.92))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(type.swipeChromeColor, lineWidth: 2)
            )
            .scaleEffect(0.92 + 0.08 * t)
            .opacity(0.35 + 0.65 * t)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

    @ViewBuilder
    private func matchBadge(_ badge: MatchBadgeStyle) -> some View {
        let content = HStack(spacing: 5) {
            Circle()
                .fill(badge.dotColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
            Text(badge.label)
                .font(.appDisplay(size: 12))
                .fontWeight(.semibold)
                .foregroundStyle(Color.black)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.95))
        )
        .overlay(
            Capsule()
                .stroke(Color.black, lineWidth: 1.2)
        )

        if let onTap = onMatchTap {
            Button(action: onTap) { content }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                .accessibilityLabel("Match details: \(badge.accessibility)")
        } else {
            content
                .accessibilityLabel("Match: \(badge.accessibility)")
        }
    }
}

/// Visual decoration for the corner match badge. Derived from a `FeedMatch`;
/// returns `nil` when there's nothing meaningful to show (e.g. missing
/// metadata for an item hydrated from warm cache).
private struct MatchBadgeStyle {
    let label: String
    let dotColor: Color
    let accessibility: String

    static func from(match: FeedMatch?) -> MatchBadgeStyle? {
        guard let match else { return nil }
        switch match.source {
        case .personalized:
            let pct = match.scorePct ?? 0
            let color = colorForBucket(match.bucket) ?? .gray
            return MatchBadgeStyle(
                label: "\(pct)%",
                dotColor: color,
                accessibility: "\(pct) percent, \(bucketWord(match.bucket)) likelihood"
            )
        case .novelty:
            return MatchBadgeStyle(
                label: "NEW",
                dotColor: .blue,
                accessibility: "exploration pick"
            )
        case .random:
            return MatchBadgeStyle(
                label: "RND",
                dotColor: .gray,
                accessibility: "random pick"
            )
        case .coldStart:
            return MatchBadgeStyle(
                label: "NEW USER",
                dotColor: .gray,
                accessibility: "not yet personalized"
            )
        }
    }

    private static func colorForBucket(_ bucket: FeedMatchBucket?) -> Color? {
        switch bucket {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .red
        case .none: return nil
        }
    }

    private static func bucketWord(_ bucket: FeedMatchBucket?) -> String {
        switch bucket {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        case .none: return "unknown"
        }
    }
}
