import Foundation
import Observation

@Observable
final class FeedViewModel {
    var items: [Item] = []
    var currentIndex = 0
    var isLoading = false
    var errorMessage: String?

    /// Set after first successful feed fetch (including empty); used for stale checks.
    private(set) var lastFeedLoadAt: Date?

    var selectedProductTypes: Set<ProductType> = []
    var selectedGenders: Set<GenderFilter> = []

    private let staleDuration: TimeInterval = 90

    /// Next N feed cards to warm (top + stacked + buffer).
    private let imagePrefetchWindow = 5

    private let initialWarmLock = NSLock()
    private var initialWarmRefreshTask: Task<Void, Never>?

    init() {
        if let warm = FeedWarmCache.loadIfValid(
            productTypes: selectedProductTypes,
            genders: selectedGenders
        ) {
            let urls = Self.feedWarmImageURLs(for: warm)
            ImageCacheService.shared.warmMemoryFromDisk(urls: urls)
            items = warm
        }
    }

    var currentItem: Item? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    var hasMoreItems: Bool {
        currentIndex < items.count
    }

    /// Tab appear: first load shows spinner unless warm cache hydrated items; later visits refresh only when stale.
    func loadIfNeeded() async {
        if lastFeedLoadAt == nil {
            if items.isEmpty {
                await loadItemsInitial()
            } else {
                initialWarmLock.lock()
                if initialWarmRefreshTask == nil {
                    initialWarmRefreshTask = Task { await self.refreshInitialFromWarmCache() }
                }
                initialWarmLock.unlock()
            }
        } else {
            await refreshIfStale()
        }
    }

    /// Forced reload (filters, explicit refresh).
    func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
            let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
            items = try await ItemService.fetchFeedItems(limit: 20, genders: genders, productTypes: productTypes)
            currentIndex = 0
            lastFeedLoadAt = Date()
            scheduleFeedImagePrefetch()
            persistFeedWarmCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadItemsInitial() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
            let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
            items = try await ItemService.fetchFeedItems(limit: 20, genders: genders, productTypes: productTypes)
            currentIndex = 0
            lastFeedLoadAt = Date()
            scheduleFeedImagePrefetch()
            persistFeedWarmCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// First launch after warm JSON hydrate: fetch fresh feed without blocking on the loading skeleton.
    private func refreshInitialFromWarmCache() async {
        defer {
            initialWarmLock.lock()
            initialWarmRefreshTask = nil
            initialWarmLock.unlock()
        }
        do {
            let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
            let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
            let fetched = try await ItemService.fetchFeedItems(limit: 20, genders: genders, productTypes: productTypes)
            applyFetchedFeed(fetched)
            lastFeedLoadAt = Date()
            scheduleFeedImagePrefetch()
            persistFeedWarmCache()
        } catch {
            // Keep warm cache items on failure
        }
    }

    /// Merges a network feed with the current stack so the visible top card stays until swiped.
    private func applyFetchedFeed(_ fetched: [Item]) {
        guard !fetched.isEmpty else { return }
        guard currentIndex < items.count else {
            items = fetched
            currentIndex = 0
            return
        }
        let pinnedItem = items[currentIndex]
        let idx = currentIndex
        if let newIndex = fetched.firstIndex(where: { $0.id == pinnedItem.id }) {
            items = fetched
            currentIndex = newIndex
        } else {
            let prefix = Array(items.prefix(idx))
            let prefixIds = Set(prefix.map(\.id))
            var tail: [Item] = []
            var seenTailIds = Set<String>()
            for item in fetched where item.id != pinnedItem.id && !prefixIds.contains(item.id) && seenTailIds.insert(item.id).inserted {
                tail.append(item)
            }
            items = prefix + [pinnedItem] + tail
        }
    }

    private func persistFeedWarmCache() {
        FeedWarmCache.save(
            items: items,
            productTypes: selectedProductTypes,
            genders: selectedGenders
        )
    }

    private static func feedWarmImageURLs(for items: [Item]) -> [URL] {
        var urls: [URL] = []
        for item in items.prefix(5) {
            guard let pair = item.imageUrlPairs.first else { continue }
            if let u = URL(string: pair.primary) { urls.append(u) }
            if let fb = pair.fallback, let u = URL(string: fb) { urls.append(u) }
        }
        return urls
    }

    private func refreshIfStale() async {
        guard let last = lastFeedLoadAt else {
            await refreshSilently()
            return
        }
        if Date().timeIntervalSince(last) < staleDuration { return }
        await refreshSilently()
    }

    private func refreshSilently() async {
        do {
            let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
            let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
            let fetched = try await ItemService.fetchFeedItems(limit: 20, genders: genders, productTypes: productTypes)
            applyFetchedFeed(fetched)
            lastFeedLoadAt = Date()
            scheduleFeedImagePrefetch()
            persistFeedWarmCache()
        } catch {
            // Keep existing items on silent failure
        }
    }

    func toggleProductType(_ type: ProductType) {
        if selectedProductTypes.contains(type) {
            selectedProductTypes.remove(type)
        } else {
            selectedProductTypes.insert(type)
        }
        Task { await loadItems() }
    }

    func toggleGender(_ gender: GenderFilter) {
        if selectedGenders.contains(gender) {
            selectedGenders.remove(gender)
        } else {
            selectedGenders.insert(gender)
        }
        Task { await loadItems() }
    }

    @discardableResult
    func recordSwipe(item: Item, action: SwipeType) async -> Bool {
        let itemId = item.id
        currentIndex += 1
        await loadMoreIfNeeded()
        scheduleFeedImagePrefetch()
        do {
            try await SwipeService.recordSwipe(itemId: itemId, type: action)
            return true
        } catch {
            currentIndex -= 1
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadMoreIfNeeded() async {
        let remaining = items.count - currentIndex
        guard remaining < 5 else { return }
        do {
            let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
            let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
            let more = try await ItemService.fetchFeedItems(limit: 20, genders: genders, productTypes: productTypes)
            guard !more.isEmpty else { return }
            let existingIds = Set(items.map(\.id))
            let newItems = more.filter { !existingIds.contains($0.id) }
            items.append(contentsOf: newItems)
            scheduleFeedImagePrefetch()
        } catch {
            // Silent fail for prefetch
        }
    }

    private func scheduleFeedImagePrefetch() {
        prefetchUpcomingImages()
        scheduleAggressiveImagePrefetch()
    }

    func prefetchUpcomingImages() {
        let end = min(currentIndex + imagePrefetchWindow, items.count)
        guard currentIndex < end else { return }
        for i in currentIndex..<end {
            let item = items[i]
            guard let pair = item.imageUrlPairs.first else { continue }
            if let url = URL(string: pair.primary) {
                ImageCacheService.shared.preload(from: url)
            }
            if let fb = pair.fallback, let url = URL(string: fb) {
                ImageCacheService.shared.preload(from: url)
            }
        }
    }

    /// Awaits `loadImage` for the upcoming window so memory cache is warm before cards appear.
    func scheduleAggressiveImagePrefetch() {
        let window = imagePrefetchWindow
        let snapshot = items
        let idx = currentIndex
        Task {
            await prefetchWindowAsync(items: snapshot, startIndex: idx, window: window)
        }
    }

    private func prefetchWindowAsync(items: [Item], startIndex: Int, window: Int) async {
        let end = min(startIndex + window, items.count)
        guard startIndex < end else { return }
        var urls: [URL] = []
        for i in startIndex..<end {
            let item = items[i]
            guard let pair = item.imageUrlPairs.first else { continue }
            if let url = URL(string: pair.primary) { urls.append(url) }
            if let fb = pair.fallback, let url = URL(string: fb) { urls.append(url) }
        }
        var seen = Set<String>()
        let unique = urls.filter { seen.insert($0.absoluteString).inserted }
        let chunkSize = 5
        var i = unique.startIndex
        while i < unique.endIndex {
            let j = unique.index(i, offsetBy: chunkSize, limitedBy: unique.endIndex) ?? unique.endIndex
            await withTaskGroup(of: Void.self) { group in
                var k = i
                while k < j {
                    let url = unique[k]
                    group.addTask {
                        _ = await ImageCacheService.shared.loadImage(from: url)
                    }
                    k = unique.index(after: k)
                }
            }
            i = j
        }
    }
}
