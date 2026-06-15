import SwiftUI

/// A single garment hanging from the wardrobe rail. Press-and-hold to lift the garment off the
/// hanger (system drag); drop on the matching mannequin slot. The system handles drag/scroll
/// coexistence, auto-scroll near edges, and the lift animation.
struct HangerCardView: View {
    let record: SwipeRecord
    var onTap: () -> Void = {}

    static let cardWidth: CGFloat = 132
    static let cardHeight: CGFloat = 220
    static let hangerHeight: CGFloat = 30
    static let hangerWidth: CGFloat = 70
    static let garmentOverlap: CGFloat = 20
    static let rodCenterY: CGFloat = 8
    static let rodThickness: CGFloat = 6

    /// Drag preview width/height — roughly matches the previous DraggedGarmentOverlay so the lift
    /// still looks like "just the garment" floating with the finger.
    private static let previewWidth: CGFloat = 110
    private static let previewHeight: CGFloat = 130

    var body: some View {
        cardBody
            .frame(width: Self.cardWidth, height: Self.cardHeight, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .modifier(DraggableForSlotModifier(record: record, previewSize: CGSize(width: Self.previewWidth, height: Self.previewHeight)))
            .accessibilityLabel(accessibilityLabel)
    }

    private var cardBody: some View {
        VStack(spacing: -Self.garmentOverlap) {
            hanger
            garmentSection
        }
    }

    private var hanger: some View {
        Image(systemName: "hanger")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: Self.hangerWidth, height: Self.hangerHeight)
            .foregroundStyle(Color.appPrimaryText.opacity(0.85))
            .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
            .accessibilityHidden(true)
    }

    private var isBottoms: Bool {
        record.item?.productType?.lowercased() == "bottoms"
    }

    /// Garment fills the card (no text strip below); the name/brand ride in a
    /// tag sticker hung at the hanger instead of floating over the art.
    private var garmentSection: some View {
        imageView
            .frame(width: Self.cardWidth, height: Self.cardHeight - Self.hangerHeight + Self.garmentOverlap)
            .scaleEffect(isBottoms ? 1.06 : 1.0, anchor: .top)
            .overlay(alignment: .top) {
                GarmentTagLabel(
                    name: record.item?.name ?? "Item",
                    brand: record.item?.brand,
                    maxWidth: Self.cardWidth - 6
                )
                .padding(.top, 1)
            }
    }

    @ViewBuilder
    private var imageView: some View {
        if let item = record.item,
           let pair = item.imageUrlPairs.first,
           let url = URL(string: pair.primary) {
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                logContext: "wardrobe-hanger",
                tightCrop: true,
                contentMode: .fit
            )
        } else {
            Rectangle().fill(Color.white.opacity(0.15))
        }
    }

    private var accessibilityLabel: String {
        let name = record.item?.name ?? "Item"
        let brand = record.item?.brand ?? ""
        return brand.isEmpty ? name : "\(name) by \(brand)"
    }
}

/// Picks the right Transferable type for the record's slot and attaches `.draggable` with a
/// custom preview view (the garment image alone). Items that don't map to any slot are not
/// draggable (still tappable for detail).
struct DraggableForSlotModifier: ViewModifier {
    let record: SwipeRecord
    let previewSize: CGSize

    func body(content: Content) -> some View {
        if let item = record.item, let slot = WardrobeViewModel.slot(for: item) {
            switch slot {
            case .hat:
                content.draggable(HatDragPayload(recordId: record.id)) { preview }
            case .top:
                content.draggable(TopDragPayload(recordId: record.id)) { preview }
            case .bottoms:
                content.draggable(BottomsDragPayload(recordId: record.id)) { preview }
            case .shoes:
                content.draggable(ShoesDragPayload(recordId: record.id)) { preview }
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let item = record.item,
               let pair = item.imageUrlPairs.first,
               let url = URL(string: pair.primary) {
                CachedAsyncImage(
                    url: url,
                    fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                    logContext: "wardrobe-drag-preview",
                    tightCrop: true,
                    contentMode: .fit
                )
            } else {
                Color.clear
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
    }
}
