import SwiftUI

/// Pop-art color scheme for a brand page banner. Picked deterministically
/// from the brand name so each brand keeps its own look across launches
/// (String.hashValue is process-seeded, so we roll our own stable hash).
struct BrandBannerTheme {
    let background: Color
    /// Decorative SF symbol floating behind the title.
    let accentIcon: String
    let accentColor: Color
    /// Fill for the piece-count sticker pill.
    let pillFill: Color
    let iconRotation: Double

    static let all: [BrandBannerTheme] = [
        // Cobalt + cyan burst (the original look).
        BrandBannerTheme(
            background: .appPopArtBlue,
            accentIcon: "burst.fill",
            accentColor: Color(red: 0.2, green: 0.95, blue: 1.0).opacity(0.5),
            pillFill: .appNeonPink,
            iconRotation: 12
        ),
        // Hot magenta + yellow seal.
        BrandBannerTheme(
            background: Color(red: 0.82, green: 0.10, blue: 0.46),
            accentIcon: "seal.fill",
            accentColor: Color(red: 1.0, green: 0.85, blue: 0.2).opacity(0.5),
            pillFill: .appPopArtBlue,
            iconRotation: -10
        ),
        // Burnt orange + cream sun.
        BrandBannerTheme(
            background: Color(red: 0.84, green: 0.40, blue: 0.05),
            accentIcon: "sun.max.fill",
            accentColor: Color(red: 1.0, green: 0.95, blue: 0.82).opacity(0.45),
            pillFill: .appNeonPink,
            iconRotation: 0
        ),
        // Deep purple + lime sparkle.
        BrandBannerTheme(
            background: Color(red: 0.36, green: 0.17, blue: 0.66),
            accentIcon: "sparkle",
            accentColor: Color(red: 0.62, green: 0.95, blue: 0.26).opacity(0.5),
            pillFill: .appNeonPink,
            iconRotation: 8
        ),
        // Forest green + pink star.
        BrandBannerTheme(
            background: Color(red: 0.05, green: 0.43, blue: 0.30),
            accentIcon: "star.fill",
            accentColor: Color(red: 1.0, green: 0.45, blue: 0.75).opacity(0.5),
            pillFill: .appPopArtBlue,
            iconRotation: -14
        ),
        // Crimson + white bolt.
        BrandBannerTheme(
            background: Color(red: 0.75, green: 0.12, blue: 0.16),
            accentIcon: "bolt.fill",
            accentColor: Color.white.opacity(0.4),
            pillFill: .appPopArtBlue,
            iconRotation: 10
        ),
        // Teal + orange dot grid.
        BrandBannerTheme(
            background: Color(red: 0.0, green: 0.42, blue: 0.52),
            accentIcon: "circle.hexagongrid.fill",
            accentColor: Color(red: 1.0, green: 0.62, blue: 0.16).opacity(0.5),
            pillFill: .appNeonPink,
            iconRotation: 6
        ),
    ]

    static func theme(for brandName: String) -> BrandBannerTheme {
        var hash: UInt64 = 5381
        for byte in brandName.lowercased().utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return all[Int(hash % UInt64(all.count))]
    }
}

/// Brand page hero: a themed color band (per-brand palette + accent icon)
/// with the comic-bold brand title, the piece count in a sticker pill, and a
/// heart button to save the brand. Scrolls away with the content; the pinned
/// filter bar below takes over.
struct BrandHeroHeader: View {
    let brandName: String
    let itemCount: Int
    let hasMore: Bool
    var theme: BrandBannerTheme? = nil
    var isSaved: Bool = false
    var onToggleSave: (() -> Void)? = nil

    private var resolvedTheme: BrandBannerTheme {
        theme ?? BrandBannerTheme.theme(for: brandName)
    }

    private var subtitleText: String {
        let countLabel = hasMore ? "\(itemCount)+" : "\(itemCount)"
        let noun = itemCount == 1 && !hasMore ? "piece" : "pieces"
        return "\(countLabel) \(noun)"
    }

    var body: some View {
        let theme = resolvedTheme
        ZStack(alignment: .leading) {
            Image(systemName: theme.accentIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(theme.iconRotation))
                .foregroundStyle(theme.accentColor)
                .offset(x: 230, y: -6)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 9) {
                Text(brandName.displayNormalizedTitle)
                    .font(.appDisplay(size: 32))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black, radius: 0, x: 2.5, y: 2.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
                Text(subtitleText.uppercased())
                    .font(.appDisplay(size: 11))
                    .tracking(0.8)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.pillFill))
                    .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                    .background(Capsule().fill(Color.black).offset(x: 2, y: 2))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .padding(.trailing, onToggleSave == nil ? 0 : 56)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .background(theme.background)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if let onToggleSave {
                saveButton(action: onToggleSave)
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(brandName.displayNormalizedTitle), \(subtitleText)")
    }

    private func saveButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isSaved ? Color.appNeonPink : Color.appPrimaryText)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white))
                .overlay(Circle().stroke(Color.black, lineWidth: 2.5))
                .background(Circle().fill(Color.black).offset(x: 2, y: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSaved ? "Unsave brand" : "Save brand")
    }
}
