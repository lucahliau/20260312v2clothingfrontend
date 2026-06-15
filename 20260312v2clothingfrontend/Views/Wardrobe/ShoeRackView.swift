import SwiftUI

/// How a shoe tile drags: slot-typed for the Fitting Room mannequin, or the
/// generic wardrobe payload for Closet drawer drops.
enum ShoeDragStyle {
    case outfitSlot
    case wardrobeItem
}

struct ShoeRackView: View {
    let records: [SwipeRecord]
    var dragStyle: ShoeDragStyle = .outfitSlot
    var onTap: (SwipeRecord) -> Void

    private static let shoeWidth: CGFloat = 86
    private static let shoeHeight: CGFloat = 64
    private static let plankHeight: CGFloat = 10
    private static let rackHeight: CGFloat = 100

    var body: some View {
        ZStack(alignment: .bottom) {
            PopArtShelfPlank(cornerRadius: 3)
                .frame(height: Self.plankHeight)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(records) { record in
                        ShoeTileView(
                            record: record,
                            width: Self.shoeWidth,
                            height: Self.shoeHeight,
                            dragStyle: dragStyle,
                            onTap: { onTap(record) }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, Self.plankHeight + 8)
            }
        }
        .frame(height: Self.rackHeight)
    }
}

private struct ShoeTileView: View {
    let record: SwipeRecord
    let width: CGFloat
    let height: CGFloat
    let dragStyle: ShoeDragStyle
    let onTap: () -> Void

    var body: some View {
        let base = tileImage
            .frame(width: width, height: height)
            .contentShape(Rectangle())

        Group {
            switch dragStyle {
            case .outfitSlot:
                base.draggable(ShoesDragPayload(recordId: record.id)) {
                    tileImage.frame(width: width, height: height)
                }
            case .wardrobeItem:
                base.draggable(WardrobeItemPayload(recordId: record.id)) {
                    tileImage.frame(width: width, height: height)
                }
                .addToCollectionMenu(recordId: record.id)
            }
        }
        .onTapGesture(perform: onTap)
        .accessibilityLabel(record.item?.name ?? "Shoe")
    }

    @ViewBuilder
    private var tileImage: some View {
        if let item = record.item,
           let pair = item.imageUrlPairs.first,
           let url = URL(string: pair.primary) {
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                logContext: "wardrobe-shoe",
                tightCrop: true,
                contentMode: .fit
            )
        } else {
            Rectangle().fill(Color.white.opacity(0.15))
        }
    }
}
