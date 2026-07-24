import Foundation
import Observation

@MainActor
private final class InitialFeedLoadCoordinator {
    private var inflight: Task<Void, Never>?

    func cancel() {
        inflight?.cancel()
        inflight = nil
    }

    func run(_ body: @escaping @MainActor () async -> Void) async {
        if let t = inflight {
            await t.value
            return
        }
        let t = Task { await body() }
        inflight = t
        await t.value
        inflight = nil
    }
}

@MainActor
@Observable
final class FeedViewModel {
    private static let feedSwipeHintSeenKey = "feedSwipeHintSeen"
    private static let feedGenderFilterUserCustomizedKey = "feedGenderFilterUserCustomized"

    var items: [Item] = []
    /// Per-card recommendation metadata keyed by item id. Populated whenever
    /// the feed is loaded/appended from the network. Warm-cached items may
    /// not have a match entry (badge simply hides for those).
    private(set) var matchesByItemId: [String: FeedMatch] = [:]
    var currentIndex = 0
    var isLoading = false
    var errorMessage: String?
    private(set) var isFeedExhausted = false
    private(set) var loadMoreErrorMessage: String?

    /// Lookup helper for views: returns `nil` when the item has no match
    /// metadata (e.g. hydrated from warm cache before the new fields were
    /// stored, or older clients).
    func match(for itemId: String) -> FeedMatch? {
        matchesByItemId[itemId]
    }

    /// Instruction caption under the feed card; hidden after first successful swipe (persisted).
    private(set) var showFeedSwipeHint: Bool

    /// Set after first successful feed fetch (including empty); used for stale checks.
    private(set) var lastFeedLoadAt: Date?

    var selectedProductTypes: Set<ProductType> = []
    var selectedGenders: Set<GenderFilter> = []

    private let staleDuration: TimeInterval = 90

    /// Feed page size. Bigger pages mean the (sometimes slow) personalized feed
    /// query runs far less often, so the deck rarely runs dry mid-swipe.
    private static let feedBatchLimit = 50

    /// Fetch the next page once the deck drops this low — early enough to hide a
    /// slow fetch behind the cards the user still has left to swipe.
    private static let loadMoreThreshold = 20

    /// Next N feed cards to warm (top + stacked + buffer). Also determines how
    /// many of the warm-cached cards have their images on disk for next launch.
    private let imagePrefetchWindow = 12

    /// Single-flight guard so concurrent swipes never fire duplicate page fetches.
    private(set) var isLoadingMore = false

    private let initialWarmLock = NSLock()
    private var initialWarmRefreshTask: Task<Void, Never>?

    private let initialFeedLoadCoordinator = InitialFeedLoadCoordinator()

    init() {
        showFeedSwipeHint = !UserDefaults.standard.bool(forKey: Self.feedSwipeHintSeenKey)
    }

    private func markFeedSwipeHintSeenIfNeeded() {
        guard showFeedSwipeHint else { return }
        UserDefaults.standard.set(true, forKey: Self.feedSwipeHintSeenKey)
        showFeedSwipeHint = false
    }

    /// Current "Discovery ↔ For You" slider value, sent with every feed request.
    private var personalization: Double { FeedPreferencesStore.shared.personalization }

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
                isLoading = true
                if hydrateFromWarmCacheIfNeeded() {
                    isLoading = false
                    initialWarmLock.lock()
                    if initialWarmRefreshTask == nil {
                        initialWarmRefreshTask = Task { await self.refreshInitialFromWarmCache() }
                    }
                    initialWarmLock.unlock()
                } else {
                    await loadItemsInitial()
                }
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

    /// Re-fetch the deck with the current personalization slider value. Called
    /// when the user moves the "Discovery ↔ For You" slider in Settings so the
    /// new mix takes effect immediately (replaces the deck, resets to the top).
    func reloadForPersonalizationChange() async {
        await loadItems()
    }

    /// Forced reload (filters, explicit refresh).
    func loadItems() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await fetchAndApplyFeedFromNetwork()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchAndApplyFeedFromNetwork() async throws {
        let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
        let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
        let result = try await ItemService.fetchFeedItemsWithMatches(limit: Self.feedBatchLimit, genders: genders, productTypes: productTypes, personalization: personalization)
        items = result.items
        replaceMatches(with: result.matches, retainingIds: Set(result.items.map(\.id)))
        currentIndex = 0
        isFeedExhausted = !result.hasMore
        loadMoreErrorMessage = nil
        lastFeedLoadAt = Date()
        scheduleFeedImagePrefetch()
        persistFeedWarmCache()
    }

    /// Replace the match map with the fresh batch; drop entries for items no
    /// longer in the stack to keep memory bounded.
    private func replaceMatches(with matches: [FeedMatch], retainingIds: Set<String>) {
        var next: [String: FeedMatch] = [:]
        for m in matches where retainingIds.contains(m.itemId) {
            next[m.itemId] = m
        }
        matchesByItemId = next
    }

    /// Merge new matches into the map without clobbering existing entries
    /// (used by paginated loads and silent refreshes).
    private func mergeMatches(_ matches: [FeedMatch]) {
        for m in matches { matchesByItemId[m.itemId] = m }
    }

    private func loadItemsInitial() async {
        await initialFeedLoadCoordinator.run {
            await self.performInitialFeedLoad()
        }
    }

    private func performInitialFeedLoad() async {
        guard !Task.isCancelled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            guard !Task.isCancelled else { return }
            try await fetchAndApplyFeedFromNetwork()
        } catch {
            if Task.isCancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    private func hydrateFromWarmCacheIfNeeded() -> Bool {
        guard let warm = FeedWarmCache.loadIfValid(
            productTypes: selectedProductTypes,
            genders: selectedGenders
        ) else { return false }
        guard !warm.isEmpty else { return false }
        // Async: the first card may show its placeholder for ~one disk read
        // instead of blocking the launch frame on file I/O + decode.
        let urls = Self.feedWarmImageURLs(for: warm)
        Task(priority: .userInitiated) {
            await ImageCacheService.shared.warmMemoryFromDisk(urls: urls)
        }
        items = warm
        currentIndex = 0
        scheduleFeedImagePrefetch()
        return true
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
            let excludedIds = exclusionIdsForNextPage()
            let result = try await ItemService.fetchFeedItemsWithMatches(
                limit: Self.feedBatchLimit,
                genders: genders,
                productTypes: productTypes,
                excludingIds: excludedIds,
                personalization: personalization
            )
            // Warm cache hydrated the SAME leftover deck we showed last launch —
            // that's the "every open shows the same posts" complaint. As long as
            // the user hasn't started swiping yet (currentIndex == 0), swap those
            // stale leftovers for the fresh, non-repeating batch the server just
            // returned (it excluded the warm ids). If they've already begun
            // swiping, append instead so we don't yank cards out from under them.
            if currentIndex == 0, !result.items.isEmpty {
                items = result.items
                replaceMatches(with: result.matches, retainingIds: Set(result.items.map(\.id)))
                currentIndex = 0
            } else {
                appendFeedPage(result.items, matches: result.matches)
            }
            isFeedExhausted = !result.hasMore
            lastFeedLoadAt = Date()
            scheduleFeedImagePrefetch()
            persistFeedWarmCache()
        } catch {
            // Keep warm cache items on failure
        }
    }

    private func persistFeedWarmCache() {
        let start = min(currentIndex, items.count)
        FeedWarmCache.save(
            items: items[start...],
            productTypes: selectedProductTypes,
            genders: selectedGenders
        )
    }

    private static func feedWarmImageURLs(for items: [Item]) -> [URL] {
        var urls: [URL] = []
        for item in items.prefix(12) {
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
            let excludedIds = exclusionIdsForNextPage()
            let result = try await ItemService.fetchFeedItemsWithMatches(
                limit: Self.feedBatchLimit,
                genders: genders,
                productTypes: productTypes,
                excludingIds: excludedIds,
                personalization: personalization
            )
            appendFeedPage(result.items, matches: result.matches)
            isFeedExhausted = !result.hasMore
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
        UserDefaults.standard.set(true, forKey: Self.feedGenderFilterUserCustomizedKey)
        if selectedGenders.contains(gender) {
            selectedGenders.remove(gender)
        } else {
            selectedGenders.insert(gender)
        }
        Task { await loadItems() }
    }

    /// When `false`, `selectedGenders` follows profile (`User.gender`) until the user edits gender filters in the sheet.
    private var feedGenderFilterUserCustomized: Bool {
        UserDefaults.standard.bool(forKey: Self.feedGenderFilterUserCustomizedKey)
    }

    /// Returns `true` when `selectedGenders` changed and the caller should refetch (e.g. `loadItems()`).
    @discardableResult
    func applyDefaultGenderFilterFromProfileIfNeeded(profileGender: String?) -> Bool {
        guard !feedGenderFilterUserCustomized else { return false }
        let next = GenderFilter.defaultSelection(forProfileGender: profileGender)
        guard next != selectedGenders else { return false }
        selectedGenders = next
        return true
    }

    /// Drops the persisted feed warm cache, removes cached images for current feed URLs, resets in-memory feed state, then refetches and preloads in the background.
    func clearPersistedFeedCache() {
        initialWarmLock.lock()
        initialWarmRefreshTask?.cancel()
        initialWarmRefreshTask = nil
        initialWarmLock.unlock()

        for item in items {
            guard let pair = item.imageUrlPairs.first else { continue }
            if let u = URL(string: pair.primary) {
                ImageCacheService.shared.removeCachedEntry(for: u)
            }
            if let fb = pair.fallback, let u = URL(string: fb) {
                ImageCacheService.shared.removeCachedEntry(for: u)
            }
        }

        FeedWarmCache.clear()
        items = []
        matchesByItemId = [:]
        currentIndex = 0
        isFeedExhausted = false
        loadMoreErrorMessage = nil
        lastFeedLoadAt = nil
        errorMessage = nil

        Task { @MainActor in
            await initialFeedLoadCoordinator.cancel()
            await initialFeedLoadCoordinator.run {
                await self.performInitialFeedLoad()
            }
        }
    }

    /// Removes the current top card when its images fail with HTTP 404 (after primary + fallback). Clears cached entries for those URLs and persists the feed.
    func removeCurrentFeedItemIfBroken404(matchingItemId itemId: String) {
        guard currentIndex < items.count, items[currentIndex].id == itemId else { return }
        let item = items[currentIndex]
        if let pair = item.imageUrlPairs.first {
            if let u = URL(string: pair.primary) {
                ImageCacheService.shared.removeCachedEntry(for: u)
            }
            if let fb = pair.fallback, let u = URL(string: fb) {
                ImageCacheService.shared.removeCachedEntry(for: u)
            }
        }
        items.remove(at: currentIndex)
        matchesByItemId.removeValue(forKey: itemId)
        persistFeedWarmCache()
        scheduleFeedImagePrefetch()
        Task { await loadMoreIfNeeded() }
    }

    @discardableResult
    func recordSwipe(item: Item, action: SwipeType) async -> Bool {
        let itemId = item.id
        currentIndex += 1
        markFeedSwipeHintSeenIfNeeded()
        scheduleFeedImagePrefetch()
        // Fire-and-forget: enqueue locally (deduped + persisted) and let the
        // background queue batch + retry. The swipe never blocks the UI, never
        // rolls the card back, and never surfaces an error — so fast swiping
        // stays smooth even when the network is slow or rate-limited.
        persistFeedWarmCache()
        // Preserve ordering: the swipe reaches the durable local queue before
        // continuation begins. The request also carries session exclusions, so
        // it remains race-free while the queue's network batch is still pending.
        Task {
            await PendingSwipeQueue.shared.enqueue(itemId: itemId, action: action)
            await loadMoreIfNeeded()
        }
        return true
    }

    func loadMoreIfNeeded() async {
        let remaining = items.count - currentIndex
        guard remaining < Self.loadMoreThreshold else { return }
        guard !isFeedExhausted else { return }
        guard !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }
        do {
            let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
            let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
            let result = try await ItemService.fetchFeedItemsWithMatches(
                limit: Self.feedBatchLimit,
                genders: genders,
                productTypes: productTypes,
                excludingIds: exclusionIdsForNextPage(),
                personalization: personalization
            )
            appendFeedPage(result.items, matches: result.matches)
            isFeedExhausted = !result.hasMore
            persistFeedWarmCache()
            scheduleFeedImagePrefetch()
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    /// Auto-recover from an apparent "all caught up" without making the user tap
    /// Refresh. The feed only truly exhausts if the whole catalog minus the
    /// user's recent swipes is empty; far more often a continuation came back
    /// empty because this session's exclusion list saturated the candidate pool.
    /// So on exhaustion we do ONE fresh reload from the top (no session
    /// exclusions — the server still hides the ~1000 most-recent swipes), which
    /// re-serves older, no-longer-recently-swiped items and keeps the feed
    /// continuous. Rate-limited so a genuinely dry catalog doesn't hot-loop.
    private var lastExhaustionRecoveryAt: Date?
    private(set) var isRecoveringFeed = false

    func attemptExhaustionRecovery() async {
        guard isFeedExhausted, !hasMoreItems, !isRecoveringFeed, !isLoading else { return }
        if let last = lastExhaustionRecoveryAt, Date().timeIntervalSince(last) < 30 { return }
        lastExhaustionRecoveryAt = Date()
        isRecoveringFeed = true
        defer { isRecoveringFeed = false }
        do {
            let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
            let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
            let result = try await ItemService.fetchFeedItemsWithMatches(
                limit: Self.feedBatchLimit,
                genders: genders,
                productTypes: productTypes,
                personalization: personalization
            )
            if !result.items.isEmpty {
                items = result.items
                replaceMatches(with: result.matches, retainingIds: Set(result.items.map(\.id)))
                currentIndex = 0
                loadMoreErrorMessage = nil
                scheduleFeedImagePrefetch()
                persistFeedWarmCache()
            }
            // If still empty, the catalog really is dry for this filter — leave
            // isFeedExhausted set so "All caught up" stays until the rate limit
            // lets us try again (or new items arrive from the crawler).
            isFeedExhausted = !result.hasMore
            lastFeedLoadAt = Date()
        } catch {
            // Transient failure — keep the exhausted state; the next appearance
            // (past the rate limit) retries.
        }
    }

    /// Include every card still in the deck plus the most recent consumed
    /// cards. Older swipes have already crossed the queue's 10-card flush
    /// threshold and are excluded by the backend's Swipe table.
    private func exclusionIdsForNextPage() -> [String] {
        Array(items.suffix(250)).map(\.id)
    }

    private func appendFeedPage(_ fetched: [Item], matches: [FeedMatch]) {
        let existingIds = Set(items.map(\.id))
        var seen = existingIds
        let newItems = fetched.filter { seen.insert($0.id).inserted }
        items.append(contentsOf: newItems)
        let appendedIds = Set(newItems.map(\.id))
        mergeMatches(matches.filter { appendedIds.contains($0.itemId) })
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
