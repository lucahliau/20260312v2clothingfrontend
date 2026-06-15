import SwiftUI

/// The Closet's shelf — bags and accessories stand on it, bottom-aligned.
/// Tap for detail; drag down into a collection stack in the drawer.
struct ClosetShelfView: View {
    let records: [SwipeRecord]
    var onTap: (SwipeRecord) -> Void

    static let shelfHeight: CGFloat = 134

    private static let tileWidth: CGFloat = 96
    private static let tileHeight: CGFloat = 92
    private static let plankHeight: CGFloat = 12

    var body: some View {
        ZStack(alignment: .bottom) {
            PopArtShelfPlank(cornerRadius: 3)
                .frame(height: Self.plankHeight)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(records) { record in
                        ShelfTileView(
                            record: record,
                            width: Self.tileWidth,
                            height: Self.tileHeight,
                            onTap: { onTap(record) }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, Self.plankHeight + 8)
            }
        }
        .frame(height: Self.shelfHeight)
    }
}

private struct ShelfTileView: View {
    let record: SwipeRecord
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void

    var body: some View {
        tileImage
            .frame(width: width, height: height, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .draggable(WardrobeItemPayload(recordId: record.id)) {
                tileImage
                    .frame(width: width, height: height)
            }
            .addToCollectionMenu(recordId: record.id)
            .accessibilityLabel(record.item?.name ?? "Accessory")
    }

    @ViewBuilder
    private var tileImage: some View {
        if let item = record.item,
           let pair = item.imageUrlPairs.first,
           let url = URL(string: pair.primary) {
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                logContext: "closet-shelf",
                tightCrop: true,
                contentMode: .fit
            )
        } else {
            Rectangle().fill(Color.white.opacity(0.15))
        }
    }
}
