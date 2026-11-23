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

/// Sort orders for the saved-items grid.
enum WardrobeSort: String, CaseIterable, Hashable, Sendable {
    case recentlyLiked
    case priceLowToHigh
    case priceHighToLow
    case brandAZ

    var displayName: String {
        switch self {
        case .recentlyLiked: return "Recently liked"
        case .priceLowToHigh: return "Price: low to high"
        case .priceHighToLow: return "Price: high to low"
        case .brandAZ: return "Brand A–Z"
        }
    }

    var shortName: String {
        switch self {
        case .recentlyLiked: return "Recent"
        case .priceLowToHigh: return "Price ↑"
        case .priceHighToLow: return "Price ↓"
        case .brandAZ: return "Brand A–Z"
        }
    }
}

/// A selectable filter value with how many saved items carry it.
struct WardrobeFilterOption: Identifiable, Hashable, Sendable {
    /// Lowercased match key.
    let id: String
    let label: String
    let count: Int
}

@Observable
final class WardrobeViewModel {
    var selectedCategory: WardrobeCategory = .all
    var outfit = Outfit()

    // MARK: - Saved grid: sort + filters (kept here so they survive tab switches)

    var sort: WardrobeSort = .recentlyLiked
    /// Lowercased brand key, or `nil` for all brands.
    var brandFilter: String?
    /// Lowercased type key (see `typeKey(for:)`), or `nil` for all types.
    var typeFilter: String?
    var lovedOnly = false

    /// Short-lived confirmation / failure banner shown over the Wardrobe.
    var toastMessage: String?
    private var toastTask: Task<Void, Never>?

    var hasActiveFilters: Bool {
        brandFilter != nil || typeFilter != nil || lovedOnly
    }

    func clearFilters() {
        brandFilter = nil
        typeFilter = nil
        lovedOnly = false
    }

    @MainActor
    func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.toastMessage = nil
        }
    }

    private static func brandKey(for item: Item) -> String? {
        guard let brand = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty else { return nil }
        return brand.lowercased()
    }

    /// One "type" per item for the filter: Shoes come from `category`, the
    /// rest from `productType` (tops, bottoms, jackets, bags, accessories…),
    /// falling back to the raw category, then "other".
    static func typeKey(for item: Item) -> String {
        if isShoe(item) { return "shoes" }
        if let type = item.productType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !type.isEmpty {
            return type
        }
        if let category = item.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !category.isEmpty {
            return category
        }
        return "other"
    }

    /// Brands present in the saved set, A–Z, with counts.
    func brandOptions(from records: [SwipeRecord]) -> [WardrobeFilterOption] {
        var counts: [String: (label: String, count: Int)] = [:]
        for record in records {
            guard let item = record.item, let key = Self.brandKey(for: item) else { continue }
            counts[key, default: (item.brand?.displayNormalizedTitle ?? key, 0)].count += 1
        }
        return counts
            .map { WardrobeFilterOption(id: $0.key, label: $0.value.label, count: $0.value.count) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Types present in the saved set, most common first.
    func typeOptions(from records: [SwipeRecord]) -> [WardrobeFilterOption] {
        var counts: [String: Int] = [:]
        for record in records {
            guard let item = record.item else { continue }
            counts[Self.typeKey(for: item), default: 0] += 1
        }
        return counts
            .map { WardrobeFilterOption(id: $0.key, label: $0.key.localizedCapitalized, count: $0.value) }
            .sorted { ($0.count, $1.label) > ($1.count, $0.label) }
    }

    /// The grid's contents: every saved record narrowed by the text query and
    /// the active filters, in the chosen order. `records` arrive newest-first
    /// from the server, which is the "recently liked" order.
    func visibleRecords(from records: [SwipeRecord], query: String) -> [SwipeRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = records.filter { record in
            guard Self.isFavorited(record) else { return false }
            if lovedOnly, record.action != .LOVE { return false }
            guard let item = record.item else {
                // No embedded item: nothing to match filters or text against.
                return q.isEmpty && brandFilter == nil && typeFilter == nil
            }
            if let brandFilter, Self.brandKey(for: item) != brandFilter { return false }
            if let typeFilter, Self.typeKey(for: item) != typeFilter { return false }
            if q.isEmpty { return true }
            if item.name.lowercased().contains(q) { return true }
            if let brand = item.brand, brand.lowercased().contains(q) { return true }
            if let category = item.category, category.lowercased().contains(q) { return true }
            return false
        }
        switch sort {
        case .recentlyLiked:
            return filtered
        case .priceLowToHigh:
            return Self.stableSorted(filtered) { a, b in
                Self.comparePrice(a.item?.priceDouble, b.item?.priceDouble, ascending: true)
            }
        case .priceHighToLow:
            return Self.stableSorted(filtered) { a, b in
                Self.comparePrice(a.item?.priceDouble, b.item?.priceDouble, ascending: false)
            }
        case .brandAZ:
            return Self.stableSorted(filtered) { a, b in
                let brandA = a.item?.brand ?? ""
                let brandB = b.item?.brand ?? ""
                // Unbranded items sink to the end.
                if brandA.isEmpty != brandB.isEmpty {
                    return brandB.isEmpty ? .orderedAscending : .orderedDescending
                }
                let byBrand = brandA.localizedCaseInsensitiveCompare(brandB)
                if byBrand != .orderedSame { return byBrand }
                return (a.item?.name ?? "").localizedCaseInsensitiveCompare(b.item?.name ?? "")
            }
        }
    }

    /// Items without a price always sort last, whichever direction.
    private static func comparePrice(_ a: Double?, _ b: Double?, ascending: Bool) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case let (x?, y?):
            if x == y { return .orderedSame }
            return (x < y) == ascending ? .orderedAscending : .orderedDescending
        }
    }

    /// Ties keep their incoming (recently-liked) order.
    private static func stableSorted(
        _ records: [SwipeRecord],
        by compare: (SwipeRecord, SwipeRecord) -> ComparisonResult
    ) -> [SwipeRecord] {
        records.enumerated().sorted { lhs, rhs in
            switch compare(lhs.element, rhs.element) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

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
