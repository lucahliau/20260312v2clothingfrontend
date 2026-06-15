import Foundation
import Observation

/// Filter chips for the wardrobe rails. Shoes are deliberately absent — they live in the bottom shoe rack.
enum WardrobeCategory: String, CaseIterable, Hashable, Sendable {
    case all
    case tops
    case bottoms
    case jackets
    case bags
    case accessories

    var displayName: String {
        switch self {
        case .all: return "All"
        case .tops: return "Tops"
        case .bottoms: return "Bottoms"
        case .jackets: return "Jackets"
        case .bags: return "Bags"
        case .accessories: return "Accessories"
        }
    }

    var productTypeRaw: String? {
        switch self {
        case .all: return nil
        case .tops: return "tops"
        case .bottoms: return "bottoms"
        case .jackets: return "jackets"
        case .bags: return "bags"
        case .accessories: return "accessories"
        }
    }

    /// The Closet rail only hangs hangable things — bags/accessories live on
    /// the shelf, so their chips are gone from the rail filter.
    static var closetRailCases: [WardrobeCategory] { [.all, .tops, .bottoms, .jackets] }
}

/// Mannequin slots, top-to-bottom.
enum OutfitSlot: String, CaseIterable, Hashable, Sendable {
    case hat
    case top
    case bottoms
    case shoes

    var label: String {
        switch self {
        case .hat: return "Hat"
        case .top: return "Top"
        case .bottoms: return "Bottoms"
        case .shoes: return "Shoes"
        }
    }
}

struct Outfit: Equatable {
    var slots: [OutfitSlot: SwipeRecord] = [:]

    var equippedIDs: Set<String> {
        Set(slots.values.map { $0.id })
    }

    var isEmpty: Bool { slots.isEmpty }

    static func == (lhs: Outfit, rhs: Outfit) -> Bool {
        let lhsIDs = lhs.slots.mapValues { $0.id }
        let rhsIDs = rhs.slots.mapValues { $0.id }
        return lhsIDs == rhsIDs
    }
}

@Observable
final class WardrobeViewModel {
    var selectedCategory: WardrobeCategory = .all
    var outfit = Outfit()

    // MARK: - Collections (the Closet drawer)

    var collections: [Collection] = []
    /// Up to three item cutouts per collection, for the folded-stack art.
    var collectionPreviews: [String: [Item]] = [:]
    var collectionsError: String?
    private var collectionsLoadedAt: Date?

    // MARK: - Classification

    static func isFavorited(_ record: SwipeRecord) -> Bool {
        record.action == .LOVE || record.action == .LIKE
    }

    static func isShoe(_ item: Item) -> Bool {
        item.category?.lowercased() == "shoes"
    }

    private static let shelfProductTypes: Set<String> = ["bags", "accessories"]

    /// Bags + accessories don't hang — they stand on the Closet shelf.
    static func isShelfItem(_ item: Item) -> Bool {
        guard let productType = item.productType?.lowercased() else { return false }
        return shelfProductTypes.contains(productType)
    }

    /// Map a clothing item to the slot it can occupy on the mannequin. Returns `nil` for items that don't fit any slot (e.g., bags).
    static func slot(for item: Item) -> OutfitSlot? {
        let cat = item.category?.lowercased() ?? ""
        let subcat = item.subcategory?.lowercased() ?? ""
        if cat == "shoes" { return .shoes }
        if cat.contains("hat") || subcat.contains("hat") || subcat.contains("cap") || subcat.contains("beanie") {
            return .hat
        }
        switch item.productType?.lowercased() {
        case "tops", "jackets": return .top
        case "bottoms": return .bottoms
        default: return nil
        }
    }

    // MARK: - Outfit

    func place(_ record: SwipeRecord, in slot: OutfitSlot) {
        outfit.slots[slot] = record
    }

    func remove(_ slot: OutfitSlot) {
        outfit.slots[slot] = nil
    }

    func clearOutfit() {
        outfit.slots.removeAll()
    }

    // MARK: - Rail / shelf / rack filters

    /// Top closet rail: tops, jackets, and anything hangable that isn't
    /// bottoms (unknown product types hang here so nothing disappears).
    func topRailRecords(from records: [SwipeRecord]) -> [SwipeRecord] {
        hangableRecords(from: records).filter {
            $0.item?.productType?.lowercased() != "bottoms"
        }
    }

    /// Bottom closet rail: bottoms only — scrolls independently of the top
    /// rail so outfits can be mixed and matched.
    func bottomRailRecords(from records: [SwipeRecord]) -> [SwipeRecord] {
        hangableRecords(from: records).filter {
            $0.item?.productType?.lowercased() == "bottoms"
        }
    }

    private func hangableRecords(from records: [SwipeRecord]) -> [SwipeRecord] {
        records.filter { record in
            guard Self.isFavorited(record), let item = record.item else { return false }
            if Self.isShoe(item) { return false }
            if Self.isShelfItem(item) { return false }
            return true
        }
    }

    func hangerRecords(from records: [SwipeRecord]) -> [SwipeRecord] {
        let equipped = outfit.equippedIDs
        return records.filter { record in
            guard Self.isFavorited(record), let item = record.item else { return false }
            if equipped.contains(record.id) { return false }
            if Self.isShoe(item) { return false }
            if Self.isShelfItem(item) { return false }
            guard let raw = selectedCategory.productTypeRaw else { return true }
            return item.productType?.lowercased() == raw
        }
    }

    func shelfRecords(from records: [SwipeRecord]) -> [SwipeRecord] {
        records.filter { record in
            guard Self.isFavorited(record), let item = record.item else { return false }
            return Self.isShelfItem(item)
        }
    }

    /// Everything the closet can show (rails + shelf + shoes) — used for the
    /// whole-closet empty state and as the search corpus.
    func allClosetRecords(from records: [SwipeRecord]) -> [SwipeRecord] {
        records.filter { record in
            Self.isFavorited(record) && record.item != nil
        }
    }

    /// Case-insensitive name/brand search over the favorited closet items.
    func searchClosetRecords(from records: [SwipeRecord], query: String) -> [SwipeRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return allClosetRecords(from: records).filter { record in
            guard let item = record.item else { return false }
            if item.name.lowercased().contains(q) { return true }
            if let brand = item.brand, brand.lowercased().contains(q) { return true }
            return false
        }
    }

    func shoeRecords(from records: [SwipeRecord]) -> [SwipeRecord] {
        let equipped = outfit.equippedIDs
        return records.filter { record in
            guard Self.isFavorited(record), let item = record.item else { return false }
            if equipped.contains(record.id) { return false }
            return Self.isShoe(item)
        }
    }

    // MARK: - Collections

    @MainActor
    func loadCollectionsIfNeeded(force: Bool = false) async {
        if !force, let at = collectionsLoadedAt, Date().timeIntervalSince(at) < 60 { return }
        do {
            collections = try await CollectionService.fetchCollections()
            collectionsLoadedAt = Date()
            collectionsError = nil
        } catch {
            collectionsError = AuthErrorMapper.message(for: error)
        }
    }

    @MainActor
    func createCollection(named name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let created = try await CollectionService.createCollection(name: trimmed)
            collections.insert(created, at: 0)
            collectionsError = nil
            return true
        } catch {
            collectionsError = AuthErrorMapper.message(for: error)
            return false
        }
    }

    @MainActor
    func loadPreviewIfNeeded(for collection: Collection) async {
        guard collectionPreviews[collection.id] == nil, (collection._count?.items ?? 0) > 0 else { return }
        guard let detail = try? await CollectionService.fetchCollection(id: collection.id) else { return }
        collectionPreviews[collection.id] = detail.items.prefix(3).map(\.item)
    }

    /// Drawer drop handler: resolve the dragged record and add its item to the
    /// collection. Refreshes counts + stack art on success.
    @MainActor
    func addRecord(withId recordId: String, from records: [SwipeRecord], to collection: Collection) async -> Bool {
        guard let record = records.first(where: { $0.id == recordId }), let item = record.item else {
            return false
        }
        do {
            try await CollectionService.addItemToCollection(collectionId: collection.id, itemId: item.id)
            collectionPreviews[collection.id] = nil
            await loadCollectionsIfNeeded(force: true)
            collectionsError = nil
            ClosetHaptics.place()
            return true
        } catch {
            collectionsError = AuthErrorMapper.message(for: error)
            return false
        }
    }

    @MainActor
    func deleteCollection(_ collection: Collection) async {
        do {
            try await CollectionService.deleteCollection(id: collection.id)
            collections.removeAll { $0.id == collection.id }
            collectionPreviews[collection.id] = nil
            collectionsError = nil
        } catch {
            collectionsError = AuthErrorMapper.message(for: error)
        }
    }

    /// Invalidate a collection's cached stack art (e.g. after removing items).
    @MainActor
    func invalidatePreview(for collectionId: String) {
        collectionPreviews[collectionId] = nil
    }

    /// Opportunistic, Wi-Fi-gated: warm the closet-drawer stack art for the
    /// first few collections so opening the drawer is instant. The rails /
    /// shelf / shoe images come from the swipe-history records, which are
    /// already prefetched at launch, so this only covers what history doesn't.
    @MainActor
    func prewarmImages(maxCollections: Int = 4, maxImages: Int = 24) async {
        var warmed = 0
        for collection in collections.prefix(maxCollections) {
            await loadPreviewIfNeeded(for: collection)
            guard let items = collectionPreviews[collection.id] else { continue }
            for item in items {
                guard warmed < maxImages,
                      let pair = item.imageUrlPairs.first,
                      let url = URL(string: pair.primary) else { continue }
                ImageCacheService.shared.preload(from: url)
                warmed += 1
            }
            if warmed >= maxImages { break }
        }
    }
}
