import SwiftUI

/// Where a hanging item's floating label sits relative to the garment.
enum ClosetLabelPlacement {
    /// Floating over the top of the garment, tucked just under the hanger
    /// (used by the top rail so labels stay clear of the rail below).
    case nearHanger
    /// Floating underneath the garment (used by the bottom rail).
    case below
}

/// A garment hanging in the Closet on a black-outlined hanger — transparent
/// cutout image, no card chrome. Every item carries a floating text label
/// (name + brand + price) on a transparent background; the top rail floats it
/// near the hanger, the bottom rail below the trousers, so labels never
/// collide with the other rail. LOVE'd items wear a heart sticker.
/// Drag (slot-agnostic payload) to drop into a collection stack; tap for detail.
struct ClosetHangerCard: View {
    let record: SwipeRecord
    var isCentered: Bool = false
    var labelPlacement: ClosetLabelPlacement = .below
    var onTap: () -> Void = {}

    static let cardWidth: CGFloat = 140
    static let hangerWidth: CGFloat = 84
    static let hangerHeight: CGFloat = 30
    static let hookCenterY: CGFloat = 6
    static let garmentOverlap: CGFloat = 10
    static let labelHeight: CGFloat = 44
    static let cardHeight: CGFloat = 192

    /// Anchor for the swing rotation — the hook point on the rod.
    static var hookAnchor: UnitPoint {
        UnitPoint(x: 0.5, y: hookCenterY / cardHeight)
    }

    private var garmentHeight: CGFloat {
        let base = Self.cardHeight - Self.hangerHeight + Self.garmentOverlap
        switch labelPlacement {
        case .nearHanger: return base
        case .below: return base - Self.labelHeight
        }
    }

    private var isBottoms: Bool {
        record.item?.productType?.lowercased() == "bottoms"
    }

    var body: some View {
        VStack(spacing: -Self.garmentOverlap) {
            hanger
            garmentStack
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .draggable(WardrobeItemPayload(recordId: record.id)) { dragPreview }
        .addToCollectionMenu(recordId: record.id)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Pieces

    private var hanger: some View {
        HangerShape()
            .stroke(
                Color.black,
                style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
            )
            .frame(width: Self.hangerWidth, height: Self.hangerHeight)
            .shadow(color: .white.opacity(0.35), radius: 1, x: 0, y: 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var garmentStack: some View {
        switch labelPlacement {
        case .nearHanger:
            garment
                .overlay(alignment: .top) {
                    // Tag sits at the hanger/garment junction, overlapping the
                    // hanger bar like a looped-on swing tag.
                    floatingLabel
                        .padding(.top, 1)
                }
        case .below:
            VStack(spacing: 0) {
                garment
                floatingLabel
                    .frame(height: Self.labelHeight, alignment: .top)
            }
        }
    }

    private var garment: some View {
        garmentImage
            .frame(width: Self.cardWidth, height: garmentHeight)
            .overlay(alignment: .topTrailing) {
                if record.action == .LOVE {
                    loveSticker
                        .padding(.top, Self.garmentOverlap + 2)
                        .padding(.trailing, 4)
                }
            }
            .scaleEffect((isCentered ? 1.0 : 0.93) * (isBottoms ? 1.06 : 1.0), anchor: .top)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isCentered)
    }

    /// Tag-sticker label hung near the hanger (see `GarmentTagLabel`).
    private var floatingLabel: some View {
        GarmentTagLabel(
            name: record.item?.name ?? "Item",
            brand: record.item?.brand,
            price: record.item?.priceDouble,
            maxWidth: Self.cardWidth - 6
        )
    }

    @ViewBuilder
    private var garmentImage: some View {
        if let item = record.item,
           let pair = item.imageUrlPairs.first,
           let url = URL(string: pair.primary) {
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                logContext: "closet-rail",
                tightCrop: true,
                contentMode: .fit
            )
        } else {
            Rectangle().fill(Color.white.opacity(0.15))
        }
    }

    private var loveSticker: some View {
        ZStack {
            Circle()
                .fill(Color.appNeonPink)
                .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                .frame(width: 22, height: 22)
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .accessibilityLabel("Loved")
    }

    @ViewBuilder
    private var dragPreview: some View {
        garmentImage
            .frame(width: 110, height: 130)
    }

    private var accessibilityLabel: String {
        let name = record.item?.name ?? "Item"
        let brand = record.item?.brand ?? ""
        return brand.isEmpty ? name : "\(name) by \(brand)"
    }
}

/// A classic hanger silhouette: hook, shoulders, and a straight lower bar.
struct HangerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let midX = rect.midX

        // Hook: open curl above the neck.
        p.move(to: CGPoint(x: midX + 6, y: rect.minY + 4))
        p.addArc(
            center: CGPoint(x: midX, y: rect.minY + 5),
            radius: 5,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        p.addLine(to: CGPoint(x: midX - 5, y: rect.minY + 8))

        // Neck down to the shoulder spread point.
        p.move(to: CGPoint(x: midX, y: rect.minY + 9))
        p.addLine(to: CGPoint(x: midX, y: rect.minY + h * 0.34))

        // Shoulders: gentle curves out to the ends.
        let shoulderY = rect.minY + h * 0.34
        let endY = rect.maxY - 3
        p.move(to: CGPoint(x: midX, y: shoulderY))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + 3, y: endY),
            control: CGPoint(x: midX - w * 0.34, y: shoulderY + 2)
        )
        p.move(to: CGPoint(x: midX, y: shoulderY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - 3, y: endY),
            control: CGPoint(x: midX + w * 0.34, y: shoulderY + 2)
        )

        // Lower bar connecting the two ends.
        p.move(to: CGPoint(x: rect.minX + 3, y: endY))
        p.addLine(to: CGPoint(x: rect.maxX - 3, y: endY))

        return p
    }
}
