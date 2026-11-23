import Foundation
import Observation

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
    func renameCollection(_ collection: Collection, to name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let updated = try await CollectionService.updateCollection(
                id: collection.id,
                update: UpdateCollectionRequest(name: trimmed)
            )
            if let idx = collections.firstIndex(where: { $0.id == collection.id }) {
                // PATCH doesn't return the item count — keep the one we have.
                collections[idx] = Collection(
                    id: updated.id,
                    userId: updated.userId,
                    name: updated.name,
                    coverUrl: updated.coverUrl,
                    createdAt: updated.createdAt,
                    updatedAt: updated.updatedAt,
                    _count: updated._count ?? collections[idx]._count
                )
            }
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
        await reloadPreview(forCollectionId: collection.id)
    }

    /// Refetches a collection's stack art. The previous art stays on screen
    /// until the new one arrives (never blanked in between).
    @MainActor
    func reloadPreview(forCollectionId collectionId: String) async {
        guard let detail = try? await CollectionService.fetchCollection(id: collectionId) else { return }
        setPreview(from: detail)
    }

    /// Updates the stack art from an already-fetched collection detail.
    @MainActor
    func setPreview(from detail: CollectionDetail) {
        collectionPreviews[detail.id] = detail.items.prefix(3).map(\.item)
    }

    /// Resolve a saved record and add its item to the collection (drawer drop
    /// or long-press menu). Refreshes counts + stack art, and reports the
    /// outcome through the toast so neither success nor failure is silent.
    @MainActor
    @discardableResult
    func addRecord(withId recordId: String, from records: [SwipeRecord], to collection: Collection) async -> Bool {
        guard let record = records.first(where: { $0.id == recordId }), let item = record.item else {
            showToast("Couldn't add that item — try again.")
            return false
        }
        do {
            try await CollectionService.addItemToCollection(collectionId: collection.id, itemId: item.id)
            collectionsError = nil
            ClosetHaptics.place()
            showToast("Added to \(collection.name)")
            await loadCollectionsIfNeeded(force: true)
            await reloadPreview(forCollectionId: collection.id)
            return true
        } catch NetworkError.serverError(let status, _, _) where status == 409 {
            showToast("Already in \(collection.name)")
            return false
        } catch {
            let message = AuthErrorMapper.message(for: error)
            collectionsError = message
            showToast("Couldn't add to \(collection.name). \(message)")
            return false
        }
    }

    @MainActor
    func deleteCollection(_ collection: Collection) async -> Bool {
        do {
            try await CollectionService.deleteCollection(id: collection.id)
            collections.removeAll { $0.id == collection.id }
            collectionPreviews[collection.id] = nil
            collectionsError = nil
            return true
        } catch {
            collectionsError = AuthErrorMapper.message(for: error)
            return false
        }
    }
}
