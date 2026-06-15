import SwiftUI

// MARK: - Shimmer primitives

private enum GhostPalette {
    static let base = Color.gray.opacity(0.14)
    static let shimmer = Color.white.opacity(0.42)
    static let cycle: TimeInterval = 1.45
}

/// Container-filling shimmer (base tint + a highlight band that sweeps left→right
/// on `GhostPalette.cycle`). Geometry-free — the sweep is driven by moving
/// gradient unit-points, so it imposes no intrinsic size and drops cleanly into
/// flexible layouts (image placeholders, avatars, cards). Shared by every loading
/// image in the app via `GhostImagePlaceholder`.
struct ShimmerFill: View {
    /// Defaults suit white cards; pass lighter values on dark backgrounds (e.g. the closet halftone).
    var base: Color = GhostPalette.base
    var highlight: Color = GhostPalette.shimmer

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t.truncatingRemainder(dividingBy: GhostPalette.cycle)) / GhostPalette.cycle)
            // Narrow highlight band sweeping across via moving unit-points.
            let lead = phase * 1.6 - 0.6
            Rectangle()
                .fill(base)
                .overlay {
                    LinearGradient(
                        colors: [.clear, highlight, .clear],
                        startPoint: UnitPoint(x: lead, y: 0.5),
                        endPoint: UnitPoint(x: lead + 0.4, y: 0.5)
                    )
                    .blendMode(.overlay)
                }
        }
    }
}

/// Rounded bar with base fill and a subtle sweeping shimmer (for use on white cards).
struct GhostBlock: View {
    var height: CGFloat
    var cornerRadius: CGFloat = 6
    /// When `nil`, expands to max width offered by parent.
    var widthFraction: CGFloat?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t.truncatingRemainder(dividingBy: GhostPalette.cycle)) / GhostPalette.cycle)

            GeometryReader { geo in
                let fullW = geo.size.width
                let w = widthFraction.map { fullW * $0 } ?? fullW
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(GhostPalette.base)
                        .frame(width: w, height: height)

                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [.clear, GhostPalette.shimmer, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(w * 0.55, 44), height: height)
                        .offset(x: -w * 0.35 + phase * (w * 1.65))
                        .blendMode(.overlay)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .frame(width: w, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
        }
    }
}

// MARK: - Settings skeleton

/// Mirrors `profileScroll` in Settings: scroll, padding, and card blocks for Account / Personal / About / Save / Log out.
struct SettingsProfileSkeletonView: View {
    private let vStackSpacing: CGFloat = 22

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: vStackSpacing) {
                accountCardSkeleton
                personalCardSkeleton
                aboutCardSkeleton
                saveRowSkeleton
                logoutRowSkeleton
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading profile")
    }

    private var accountCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.22)
            VStack(alignment: .leading, spacing: 12) {
                labeledLineSkeleton(valueWidth: 0.72)
                Divider().opacity(0.2)
                labeledLineSkeleton(valueWidth: 0.58)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private var personalCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 14) {
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.32)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<5, id: \.self) { i in
                    labeledLineSkeleton(valueWidth: i == 2 ? 0.42 : 0.88)
                    if i < 4 {
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private var aboutCardSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.18)
            GhostBlock(height: 100, cornerRadius: 8, widthFraction: 1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private var saveRowSkeleton: some View {
        GhostBlock(height: 22, cornerRadius: 8, widthFraction: 0.38)
            .frame(maxWidth: .infinity)
            .padding(18)
            .popArtCardContainer()
    }

    private var logoutRowSkeleton: some View {
        GhostBlock(height: 22, cornerRadius: 8, widthFraction: 0.28)
            .frame(maxWidth: .infinity)
            .padding(18)
            .popArtCardContainer()
    }

    private func labeledLineSkeleton(valueWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.28)
            GhostBlock(height: 17, cornerRadius: 5, widthFraction: valueWidth)
        }
    }
}

// MARK: - History skeleton

private struct HistoryThumbShimmer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t.truncatingRemainder(dividingBy: GhostPalette.cycle)) / GhostPalette.cycle)
            GeometryReader { geo in
                let w = geo.size.width
                LinearGradient(
                    colors: [.clear, GhostPalette.shimmer, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w * 0.5)
                .offset(x: -w * 0.25 + phase * (w * 1.5))
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// Single history row layout for loading overlays (matches `historyRow`).
struct SwipeHistoryRowSkeletonView: View {
    static let thumbSize: CGFloat = 64

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(GhostPalette.base)
                .frame(width: Self.thumbSize, height: Self.thumbSize)
                .overlay { HistoryThumbShimmer() }
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                GhostBlock(height: 17, cornerRadius: 5, widthFraction: 0.92)
                GhostBlock(height: 15, cornerRadius: 5, widthFraction: 0.45)
            }
            Spacer(minLength: 8)
            GhostBlock(height: 22, cornerRadius: 11, widthFraction: 1)
                .frame(width: 56)
            GhostBlock(height: 14, cornerRadius: 4, widthFraction: 1)
                .frame(width: 10)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Mirrors `historyScroll`: section headers + row cards with thumb and text lines.
struct SwipeHistorySkeletonView: View {
    private static let sectionSpacing: CGFloat = 26
    private static let rowSpacing: CGFloat = 12
    private static let headerToRowsSpacing: CGFloat = 10

    private let sectionRowCounts = [3, 4]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.sectionSpacing) {
                ForEach(0..<sectionRowCounts.count, id: \.self) { i in
                    historySectionSkeleton(rowCount: sectionRowCounts[i])
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading history")
    }

    private func historySectionSkeleton(rowCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Self.headerToRowsSpacing) {
            GhostBlock(height: 11, cornerRadius: 4, widthFraction: 0.2)
                .padding(.horizontal, 2)

            LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(0..<rowCount, id: \.self) { _ in
                    SwipeHistoryRowSkeletonView()
                        .popArtCardContainer()
                }
            }
        }
    }
}

// MARK: - Feed / swipe card skeleton

private let feedTitleBandSkeletonHeight: CGFloat = 56
private let feedCardImageAreaHeightPerWidth: CGFloat = 4.0 / 3.0

/// Matches `SwipeCardView` chrome: image area + pink title band with ghost lines.
struct SwipeCardSkeletonView: View {
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let cappedHeight = width * feedCardImageAreaHeightPerWidth + feedTitleBandSkeletonHeight
            let totalHeight = min(geo.size.height, cappedHeight)
            let size = CGSize(width: width, height: totalHeight)
            let imageH = max(totalHeight - feedTitleBandSkeletonHeight, 0)
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    GhostBlock(height: imageH, cornerRadius: 0)
                        .frame(width: size.width, height: imageH)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    GhostBlock(height: 17, cornerRadius: 5, widthFraction: 0.88)
                    GhostBlock(height: 14, cornerRadius: 4, widthFraction: 0.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(minWidth: size.width, maxWidth: size.width, minHeight: feedTitleBandSkeletonHeight, alignment: .leading)
                .background(Color.appNeonPink)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: PopArtCardStyle.strokeWidth)
                }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Two stacked card skeletons matching `FeedView`’s `cardStack`.
struct FeedCardStackSkeletonView: View {
    var body: some View {
        ZStack {
            SwipeCardSkeletonView()
                .scaleEffect(0.98)
                .offset(y: 6)
            SwipeCardSkeletonView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Explore skeletons

/// 2×2 collage placeholder (matches `BrandImageCollage` layout). No card chrome — use inside a single `popArtCardContainer`.
struct FeaturedBrandCollageSkeleton: View {
    var body: some View {
        GeometryReader { geo in
            let cell = (geo.size.width - 2) / 2
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    GhostBlock(height: cell, cornerRadius: 0)
                        .frame(width: cell, height: cell)
                    GhostBlock(height: cell, cornerRadius: 0)
                        .frame(width: cell, height: cell)
                }
                HStack(spacing: 2) {
                    GhostBlock(height: cell, cornerRadius: 0)
                        .frame(width: cell, height: cell)
                    GhostBlock(height: cell, cornerRadius: 0)
                        .frame(width: cell, height: cell)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct FeaturedBrandRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeaturedBrandCollageSkeleton()

            GhostBlock(height: 20, cornerRadius: 5, widthFraction: 0.72)
            GhostBlock(height: 14, cornerRadius: 4, widthFraction: 0.38)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .popArtCardContainer()
    }
}

struct FeaturedBrandsSectionSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.28)
                .padding(.horizontal, 2)
            ForEach(0..<3, id: \.self) { _ in
                FeaturedBrandRowSkeleton()
            }
        }
    }
}

struct ExploreProductCellSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let s = geo.size.width
                GhostBlock(height: s, cornerRadius: 12)
                    .frame(width: s, height: s)
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black, lineWidth: 2)
            )
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.92)
            GhostBlock(height: 12, cornerRadius: 4, widthFraction: 0.45)
        }
    }
}

struct ExploreProductGridSkeletonView: View {
    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)
    ]
    let cellCount: Int

    init(cellCount: Int = 8) {
        self.cellCount = cellCount
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<cellCount, id: \.self) { _ in
                ExploreProductCellSkeleton()
            }
        }
    }
}

struct ExploreBrandSearchRowSkeleton: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                GhostBlock(height: 17, cornerRadius: 5, widthFraction: 0.55)
                GhostBlock(height: 14, cornerRadius: 4, widthFraction: 0.35)
            }
            Spacer(minLength: 8)
            GhostBlock(height: 14, cornerRadius: 4, widthFraction: 1)
                .frame(width: 10)
        }
        .padding(14)
        .popArtCardContainer()
    }
}

struct ExploreSearchLoadingSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.18)
                .padding(.horizontal, 2)
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    ExploreBrandSearchRowSkeleton()
                }
            }
            GhostBlock(height: 13, cornerRadius: 4, widthFraction: 0.22)
                .padding(.horizontal, 2)
                .padding(.top, 4)
            ExploreProductGridSkeletonView(cellCount: 6)
        }
    }
}

// MARK: - Friends skeletons

struct FriendsSearchRowSkeleton: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(GhostPalette.base)
                .frame(width: 48, height: 48)
                .overlay { HistoryThumbShimmer() }
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                GhostBlock(height: 17, cornerRadius: 5, widthFraction: 0.92)
                GhostBlock(height: 15, cornerRadius: 5, widthFraction: 0.45)
            }
            Spacer(minLength: 8)
            GhostBlock(height: 14, cornerRadius: 4, widthFraction: 1)
                .frame(width: 10)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FriendsListSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                FriendsSearchRowSkeleton()
                    .popArtCardContainer()
            }
        }
    }
}

// MARK: - Wardrobe closet skeleton

/// Mirrors `ClosetView`: two horizontal hanger rails + a shelf row + a shoe
/// rack. Shown on first load (before the swipe history arrives) so the closet
/// shimmers instead of flashing the per-rail empty states. Lighter ghosts than
/// the white-card skeletons since the closet sits on the dark halftone wall.
struct ClosetSkeletonView: View {
    private let base = Color.white.opacity(0.16)
    private let highlight = Color.white.opacity(0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            railHeader
            hangerRail(count: 4, height: 150)
            railHeader.padding(.top, 6)
            hangerRail(count: 4, height: 168)
            railHeader.padding(.top, 6)
            tileRow(count: 4, side: 86)
            railHeader.padding(.top, 6)
            tileRow(count: 4, side: 96)
        }
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    private var railHeader: some View {
        block(width: 150, height: 20, cornerRadius: 6)
            .padding(.leading, 16)
            .padding(.top, 4)
    }

    private func hangerRail(count: Int, height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { _ in
                    block(width: 120, height: height, cornerRadius: 14)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollDisabled(true)
    }

    private func tileRow(count: Int, side: CGFloat) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                block(width: side, height: side, cornerRadius: 12)
            }
        }
        .padding(.horizontal, 16)
    }

    /// Pop-art ghost tile: shimmer fill + the black outline used across the closet.
    private func block(width: CGFloat, height: CGFloat, cornerRadius: CGFloat) -> some View {
        ShimmerFill(base: base, highlight: highlight)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.black, lineWidth: 2.5)
            )
    }
}

// MARK: - Conversation list row skeleton

/// Avatar circle + two text lines, matching a conversations-list row. Lives
/// here (was inline in ConversationsListView) so every skeleton shares one
/// shimmer treatment.
struct ConversationRowSkeleton: View {
    var body: some View {
        HStack(spacing: 14) {
            ShimmerFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 8) {
                GhostBlock(height: 14, cornerRadius: 4, widthFraction: 0.55)
                GhostBlock(height: 12, cornerRadius: 4, widthFraction: 1)
            }
        }
        .padding(15)
    }
}

// MARK: - Conversation thread skeleton

/// Placeholder bubbles for a DM thread's initial load — alternating incoming
/// (leading) and outgoing (trailing) shimmer bubbles of varied widths.
struct ConversationThreadSkeletonView: View {
    /// (isOutgoing, width, height) — a believable back-and-forth.
    private let bubbles: [(Bool, CGFloat, CGFloat)] = [
        (false, 150, 38), (true, 110, 38), (false, 210, 56),
        (true, 170, 38), (false, 90, 38), (true, 200, 56),
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(bubbles.enumerated()), id: \.offset) { _, b in
                HStack {
                    if b.0 { Spacer(minLength: 60) }
                    ShimmerFill()
                        .frame(width: b.1, height: b.2)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    if !b.0 { Spacer(minLength: 60) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

