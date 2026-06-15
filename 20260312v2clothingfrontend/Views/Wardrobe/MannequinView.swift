import SwiftUI

/// Mannequin: four clothing-slot drop targets stacked vertically.
/// Empty slots show a rounded-square dashed outline with the matching SF Symbol; filled slots show the item image.
/// Tops and bottoms align along an alpha-anchored joint so the shirt hem meets the trouser waist visually.
struct MannequinView: View {
    let outfit: Outfit
    var onTapEquipped: (OutfitSlot) -> Void
    /// Called when the user drops a draggable record onto a slot. The parent looks up the
    /// `SwipeRecord` by id and applies it via the view model.
    var onDropRecord: (OutfitSlot, String) -> Void

    static let mannequinWidth: CGFloat = 220
    static let mannequinHeight: CGFloat = 340

    // Slot centers chosen so placeholders touch at the top↔bottoms boundary but otherwise have small gaps.
    // (When filled, top and bottoms still overlap at jointY via anchor-edge positioning below.)
    private static let hatCenterY: CGFloat = 31         // hat 64×52 → y=5..57
    private static let topCenterY: CGFloat = 113        // top 110×96 → y=65..161  (8pt gap below hat)
    private static let bottomsCenterY: CGFloat = 217    // bottoms 92×112 → y=161..273  (touches top)
    private static let shoesCenterY: CGFloat = 305      // shoes 100×50 → y=280..330  (7pt gap below bottoms)
    /// Joint line where the shirt hem meets the trouser waist when both are filled.
    private static let jointY: CGFloat = 161
    /// Small downward overlap so the shirt hem covers the waistband, not the other way around.
    private static let jointOverlap: CGFloat = 6

    // Slot hit-test sizes (also used as placeholder sizes). Stable — drop targets don't change with content.
    private static let hatSize: CGSize = .init(width: 64, height: 52)
    private static let topSize: CGSize = .init(width: 110, height: 96)
    private static let bottomsSize: CGSize = .init(width: 92, height: 112)
    private static let shoesSize: CGSize = .init(width: 100, height: 50)

    /// Target on-screen width (points) of the shared top-hem / trouser-waist joint.
    private static let jointWidth: CGFloat = 78
    /// Clamp range for the on-screen width of a filled top or bottoms — keeps anchor math from blowing up.
    private static let minFilledWidth: CGFloat = 70
    private static let maxFilledWidth: CGFloat = 150
    /// Cap rendered heights so a long garment can't overflow into neighbouring slots.
    private static let maxTopHeight: CGFloat = 130
    private static let maxBottomsHeight: CGFloat = 150

    private static let defaultHatWidth: CGFloat = 78
    private static let defaultShoesWidth: CGFloat = 110

    @State private var metricsByID: [String: GarmentMetrics] = [:]
    /// Per-slot drop-hover state. SwiftUI's `.dropDestination(isTargeted:)` filters by Transferable
    /// type, so a slot only highlights when a compatible garment is hovered over it.
    @State private var hoveringSlots: [OutfitSlot: Bool] = [:]

    var body: some View {
        ZStack {
            // Layer 1: drop-destination hit-zones, one per slot, each typed to its matching payload.
            dropZone(.hat)
            dropZone(.top)
            dropZone(.bottoms)
            dropZone(.shoes)

            // Layer 2: slot content (placeholder icon or filled image), z-ordered so hat sits on top, shoes below bottoms.
            slotContent(.hat).zIndex(4)
            slotContent(.top).zIndex(3)
            slotContent(.bottoms).zIndex(2)
            slotContent(.shoes).zIndex(2.5)
        }
        .frame(width: Self.mannequinWidth, height: Self.mannequinHeight)
        .task(id: outfit.equippedIDs) {
            await loadMetricsForEquipped()
        }
    }

    // MARK: - Drop zones

    @ViewBuilder
    private func dropZone(_ slot: OutfitSlot) -> some View {
        let size = hitSize(for: slot)
        let baseView = Color.clear
            .frame(width: size.width, height: size.height)
            .position(x: Self.mannequinWidth / 2, y: hitCenterY(for: slot))

        switch slot {
        case .hat:
            baseView.dropDestination(for: HatDragPayload.self) { items, _ in
                applyDrop(slot: .hat, recordId: items.first?.recordId)
            } isTargeted: { hoveringSlots[.hat] = $0 }
        case .top:
            baseView.dropDestination(for: TopDragPayload.self) { items, _ in
                applyDrop(slot: .top, recordId: items.first?.recordId)
            } isTargeted: { hoveringSlots[.top] = $0 }
        case .bottoms:
            baseView.dropDestination(for: BottomsDragPayload.self) { items, _ in
                applyDrop(slot: .bottoms, recordId: items.first?.recordId)
            } isTargeted: { hoveringSlots[.bottoms] = $0 }
        case .shoes:
            baseView.dropDestination(for: ShoesDragPayload.self) { items, _ in
                applyDrop(slot: .shoes, recordId: items.first?.recordId)
            } isTargeted: { hoveringSlots[.shoes] = $0 }
        }
    }

    private func applyDrop(slot: OutfitSlot, recordId: String?) -> Bool {
        guard let recordId else { return false }
        onDropRecord(slot, recordId)
        return true
    }

    // MARK: - Content rendering

    @ViewBuilder
    private func slotContent(_ slot: OutfitSlot) -> some View {
        let isHovering = hoveringSlots[slot] == true
        if let record = outfit.slots[slot] {
            let size = renderSize(for: slot, record: record)
            let center = centerPoint(for: slot, size: size)
            FilledSlotView(record: record, size: size) {
                onTapEquipped(slot)
            }
            .position(center)
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.18), value: isHovering)
        } else {
            let size = hitSize(for: slot)
            SlotPlaceholderView(slot: slot, size: size, isHovering: isHovering)
                .position(x: Self.mannequinWidth / 2, y: hitCenterY(for: slot))
        }
    }

    // MARK: - Slot geometry

    private func hitSize(for slot: OutfitSlot) -> CGSize {
        switch slot {
        case .hat: return Self.hatSize
        case .top: return Self.topSize
        case .bottoms: return Self.bottomsSize
        case .shoes: return Self.shoesSize
        }
    }

    private func hitCenterY(for slot: OutfitSlot) -> CGFloat {
        switch slot {
        case .hat: return Self.hatCenterY
        case .top: return Self.topCenterY
        case .bottoms: return Self.bottomsCenterY
        case .shoes: return Self.shoesCenterY
        }
    }

    /// Compute the on-screen size for a filled slot. Falls back to hit-zone size while metrics are still loading.
    private func renderSize(for slot: OutfitSlot, record: SwipeRecord) -> CGSize {
        guard let metrics = metricsByID[record.id] else { return hitSize(for: slot) }
        let imgSize = metrics.image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return hitSize(for: slot) }

        var width = anchorDisplayWidth(for: slot, metrics: metrics)
        var height = width * (imgSize.height / imgSize.width)

        // Height cap (keeps garments from invading neighbouring slots).
        if let maxH = maxHeight(for: slot), height > maxH {
            height = maxH
            width = height * (imgSize.width / imgSize.height)
        }

        // Final width clamp so a clamped height didn't produce something silly.
        width = min(max(width, Self.minFilledWidth), Self.maxFilledWidth)
        height = width * (imgSize.height / imgSize.width)
        return CGSize(width: width, height: height)
    }

    private func anchorDisplayWidth(for slot: OutfitSlot, metrics: GarmentMetrics) -> CGFloat {
        switch slot {
        case .top:
            let frac = max(0.25, metrics.anchors.bottomWidthFraction)
            let raw = Self.jointWidth / frac
            return min(max(raw, Self.minFilledWidth), Self.maxFilledWidth)
        case .bottoms:
            let frac = max(0.25, metrics.anchors.topWidthFraction)
            let raw = Self.jointWidth / frac
            return min(max(raw, Self.minFilledWidth), Self.maxFilledWidth)
        case .hat:
            return Self.defaultHatWidth
        case .shoes:
            return Self.defaultShoesWidth
        }
    }

    private func maxHeight(for slot: OutfitSlot) -> CGFloat? {
        switch slot {
        case .top: return Self.maxTopHeight
        case .bottoms: return Self.maxBottomsHeight
        default: return nil
        }
    }

    /// Position the slot image so the top/bottoms align at the joint Y; hat and shoes use their slot center.
    private func centerPoint(for slot: OutfitSlot, size: CGSize) -> CGPoint {
        let x = Self.mannequinWidth / 2
        switch slot {
        case .hat:
            return CGPoint(x: x, y: Self.hatCenterY)
        case .top:
            // Bottom edge of image lands at jointY + small overlap.
            return CGPoint(x: x, y: Self.jointY + Self.jointOverlap - size.height / 2)
        case .bottoms:
            // Top edge of image lands at jointY.
            return CGPoint(x: x, y: Self.jointY + size.height / 2)
        case .shoes:
            return CGPoint(x: x, y: Self.shoesCenterY)
        }
    }

    // MARK: - Metrics loading

    private func loadMetricsForEquipped() async {
        for (_, record) in outfit.slots {
            guard let item = record.item,
                  let pair = item.imageUrlPairs.first,
                  let url = URL(string: pair.primary) else { continue }
            let key = url.absoluteString
            if metricsByID[record.id] != nil { continue }
            if let cached = GarmentMetricsCache.shared.get(key) {
                metricsByID[record.id] = cached
                continue
            }
            let fallback = pair.fallback.flatMap { URL(string: $0) }
            if let metrics = await loadAndMeasure(url: url, fallback: fallback) {
                GarmentMetricsCache.shared.set(metrics, for: key)
                await MainActor.run {
                    metricsByID[record.id] = metrics
                }
            }
        }
    }

    private func loadAndMeasure(url: URL, fallback: URL?) async -> GarmentMetrics? {
        var raw = await ImageCacheService.shared.loadImage(from: url)
        if raw == nil, let fallback {
            raw = await ImageCacheService.shared.loadImage(from: fallback)
        }
        guard let raw else { return nil }
        let trimmed = raw.trimmedToOpaque()
        let anchors = trimmed.garmentAnchors()
        return GarmentMetrics(image: trimmed, anchors: anchors)
    }
}

// MARK: - Filled slot

private struct FilledSlotView: View {
    let record: SwipeRecord
    let size: CGSize
    let onTap: () -> Void

    var body: some View {
        Group {
            if let item = record.item,
               let pair = item.imageUrlPairs.first,
               let url = URL(string: pair.primary) {
                CachedAsyncImage(
                    url: url,
                    fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                    logContext: "wardrobe-mannequin",
                    tightCrop: true,
                    contentMode: .fit
                )
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityLabel(record.item?.name ?? "Item")
        .accessibilityHint("Tap to put back on the rack")
    }
}

// MARK: - Empty-slot placeholder

private struct SlotPlaceholderView: View {
    let slot: OutfitSlot
    let size: CGSize
    let isHovering: Bool

    var body: some View {
        let stroke = Color.white.opacity(isHovering ? 0.95 : 0.55)
        let fill = Color.white.opacity(isHovering ? 0.20 : 0.08)
        let iconColor = Color.white.opacity(isHovering ? 0.95 : 0.70)

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(fill)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    stroke,
                    style: StrokeStyle(lineWidth: isHovering ? 2 : 1.5, dash: [5, 4])
                )
            Image(systemName: iconName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(iconColor)
                .padding(iconPadding)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("\(slot.label) slot")
    }

    /// SF Symbols for each slot. Selected for general iOS availability; tweak if any render as missing on this OS.
    private var iconName: String {
        switch slot {
        case .hat: return "cap.fill"
        case .top: return "tshirt.fill"
        case .bottoms: return "figure.stand"
        case .shoes: return "shoe.fill"
        }
    }

    private var iconPadding: CGFloat {
        switch slot {
        case .hat: return 12
        case .top: return 18
        case .bottoms: return 14
        case .shoes: return 12
        }
    }
}
