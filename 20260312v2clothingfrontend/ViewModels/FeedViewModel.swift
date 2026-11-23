import Foundation
import Observation

@MainActor
@Observable
final class FeedViewModel {
    private static let feedSwipeHintSeenKey = "feedSwipeHintSeen"
    private static let feedGenderFilterUserCustomizedKey = "feedGenderFilterUserCustomized"
    private static let feedSelectedProductTypesKey = "feedSelectedProductTypes"
    private static let feedSelectedGendersKey = "feedSelectedGenders"

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
    /// Set when a full (re)load failed and there is nothing to show — the Feed
    /// renders this with a Retry instead of "No items".
    private(set) var feedLoadErrorMessage: String?

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

    /// Persisted, so a relaunch keeps the same filters (and the warm cache,
    /// which is fingerprinted by them, still matches).
    var selectedProductTypes: Set<ProductType> = [] {
        didSet {
            guard selectedProductTypes != oldValue else { return }
            UserDefaults.standard.set(selectedProductTypes.map(\.rawValue).sorted(), forKey: Self.feedSelectedProductTypesKey)
        }
    }
    var selectedGenders: Set<GenderFilter> = [] {
        didSet {
            guard selectedGenders != oldValue else { return }
            UserDefaults.standard.set(selectedGenders.map(\.rawValue).sorted(), forKey: Self.feedSelectedGendersKey)
        }
    }

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

    /// Bumped whenever the deck's defining query changes (filters, explicit
    /// reload, cache clear). Every response captures the generation it was
    /// requested under and is dropped if a newer one exists, so the last
    /// *request* wins rather than the last response to arrive, and an in-flight
    /// load-more can't append old-filter cards.
    @ObservationIgnored private var feedGeneration = 0
    @ObservationIgnored private var filterReloadTask: Task<Void, Never>?
    @ObservationIgnored private var initialWarmRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var warmCacheSaveTask: Task<Void, Never>?
    @ObservationIgnored private var imagePrefetchTask: Task<Void, Never>?

    /// True while the user is dragging the top card or it is flying off. A
    /// background refresh must not replace the deck then (the card under the
    /// finger would vanish and the pending swipe would skip a fresh card).
    @ObservationIgnored private var isCardInteractionActive = false

    /// The most recent swipe, kept so it can be undone once.
    private(set) var lastSwipe: (item: Item, action: SwipeType)?

    init() {
        showFeedSwipeHint = !UserDefaults.standard.bool(forKey: Self.feedSwipeHintSeenKey)
        let defaults = UserDefaults.standard
        if let raw = defaults.stringArray(forKey: Self.feedSelectedProductTypesKey) {
            selectedProductTypes = Set(raw.compactMap(ProductType.init(rawValue:)))
        }
        if let raw = defaults.stringArray(forKey: Self.feedSelectedGendersKey) {
            selectedGenders = Set(raw.compactMap(GenderFilter.init(rawValue:)))
        }
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

    // MARK: - Loading

    /// One feed request for the current filters + personalization.
    private func fetchFeed(excludingIds: [String] = []) async throws -> (items: [Item], matches: [FeedMatch], hasMore: Bool) {
        let genders = selectedGenders.isEmpty ? nil : selectedGenders.map(\.rawValue)
        let productTypes = selectedProductTypes.isEmpty ? nil : selectedProductTypes.map(\.rawValue)
        return try await ItemService.fetchFeedItemsWithMatches(
            limit: Self.feedBatchLimit,
            genders: genders,
            productTypes: productTypes,
            excludingIds: excludingIds,
            personalization: personalization
        )
    }

    /// Tab appear: first load shows spinner unless warm cache hydrated items; later visits refresh only when stale.
    func loadIfNeeded() async {
        if lastFeedLoadAt == nil {
            if items.isEmpty {
                guard !isLoading else { return }
                if hydrateFromWarmCacheIfNeeded() {
                    startInitialWarmRefreshIfNeeded()
                } else {
                    await loadItems()
                }
            } else {
                startInitialWarmRefreshIfNeeded()
            }
        } else {
            await refreshIfStale()
        }
    }

    private func startInitialWarmRefreshIfNeeded() {
        guard initialWarmRefreshTask == nil else { return }
        initialWarmRefreshTask = Task { [weak self] in
            await self?.refreshInitialFromWarmCache()
            self?.initialWarmRefreshTask = nil
        }
    }

    /// Re-fetch the deck with the current personalization slider value. Called
    /// when the user moves the "Discovery ↔ For You" slider in Settings so the
    /// new mix takes effect immediately (replaces the deck, resets to the top).
    func reloadForPersonalizationChange() async {
        await loadItems()
    }

    /// The server just became reachable again (see `ServerUnreachableBanner`):
    /// refill the deck if it ran dry or never loaded; otherwise leave the
    /// user's current cards alone and just top up.
    func reloadAfterServerRecovery() async {
        errorMessage = nil
        if items.isEmpty || !hasMoreItems {
            await loadItems()
        } else {
            await loadMoreIfNeeded()
        }
    }

    /// Forced reload (filters, explicit refresh). Supersedes every feed request
    /// already in flight.
    func loadItems() async {
        feedGeneration += 1
        let generation = feedGeneration
        isLoading = true
        errorMessage = nil
        feedLoadErrorMessage = nil
        do {
            let result = try await fetchFeed()
            guard generation == feedGeneration else { return }
            items = result.items
            replaceMatches(with: result.matches, retainingIds: Set(result.items.map(\.id)))
            currentIndex = 0
            lastSwipe = nil
            isFeedExhausted = !result.hasMore
            loadMoreErrorMessage = nil
            lastFeedLoadAt = Date()
            scheduleFeedImagePrefetch()
            persistFeedWarmCache()
        } catch {
            guard generation == feedGeneration else { return }
            if !error.isCancellation {
                if hasMoreItems {
                    // Cards are still on screen (e.g. a personalization reload):
                    // tell the user, keep the deck.
                    errorMessage = error.localizedDescription
                } else {
                    feedLoadErrorMessage = error.localizedDescription
                }
            }
        }
        isLoading = false
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
        let generation = feedGeneration
        do {
            let result = try await fetchFeed(excludingIds: exclusionIdsForNextPage())
            guard generation == feedGeneration else { return }
            // Warm cache hydrated the SAME leftover deck we showed last launch —
            // that's the "every open shows the same posts" complaint. As long as
            // the user hasn't started swiping yet (currentIndex == 0) and isn't
            // mid-drag on the top card, swap those stale leftovers for the fresh,
            // non-repeating batch the server just returned (it excluded the warm
            // ids). Otherwise append, so we never yank a card out from under a
            // finger or let a swipe that is mid-exit skip a fresh card.
            if currentIndex == 0, !isCardInteractionActive, !result.items.isEmpty {
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

    /// Debounced: a burst of swipes produces one snapshot. The (small) encode
    /// runs here; the file write happens on a background queue.
    private func persistFeedWarmCache() {
        warmCacheSaveTask?.cancel()
        warmCacheSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            let start = min(self.currentIndex, self.items.count)
            FeedWarmCache.save(
                items: self.items[start...],
                productTypes: self.selectedProductTypes,
                genders: self.selectedGenders
            )
        }
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
        if let last = lastFeedLoadAt, Date().timeIntervalSince(last) < staleDuration { return }
        await refreshSilently()
    }

    private func refreshSilently() async {
        let generation = feedGeneration
        do {
            let result = try await fetchFeed(excludingIds: exclusionIdsForNextPage())
            guard generation == feedGeneration else { return }
            appendFeedPage(result.items, matches: result.matches)
            isFeedExhausted = !result.hasMore
            lastFeedLoadAt = Date()
            scheduleFeedImagePrefetch()
            persistFeedWarmCache()
        } catch {
            // Keep existing items on silent failure
        }
    }

    // MARK: - Filters

    /// Filter changes invalidate everything in flight immediately, then reload
    /// once after a short pause — tapping three options in the sheet is one
    /// request for the final selection, not three racing ones.
    private func scheduleFilterReload() {
        feedGeneration += 1
        isLoading = true
        filterReloadTask?.cancel()
        filterReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadItems()
        }
    }

    func toggleProductType(_ type: ProductType) {
        if selectedProductTypes.contains(type) {
            selectedProductTypes.remove(type)
        } else {
            selectedProductTypes.insert(type)
        }
        scheduleFilterReload()
    }

    func toggleGender(_ gender: GenderFilter) {
        UserDefaults.standard.set(true, forKey: Self.feedGenderFilterUserCustomizedKey)
        if selectedGenders.contains(gender) {
            selectedGenders.remove(gender)
        } else {
            selectedGenders.insert(gender)
        }
        scheduleFilterReload()
    }

    /// "Clear filters" in the empty state. An explicit choice, so the gender
    /// filter counts as customised (the profile default won't silently return).
    func clearFilters() {
        if !selectedGenders.isEmpty {
            UserDefaults.standard.set(true, forKey: Self.feedGenderFilterUserCustomizedKey)
        }
        selectedProductTypes = []
        selectedGenders = []
        scheduleFilterReload()
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
        initialWarmRefreshTask?.cancel()
        initialWarmRefreshTask = nil
        warmCacheSaveTask?.cancel()
        warmCacheSaveTask = nil

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
        lastSwipe = nil
        isFeedExhausted = false
        loadMoreErrorMessage = nil
        lastFeedLoadAt = nil
        errorMessage = nil

        Task { await loadItems() }
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

    // MARK: - Swiping

    /// The top card reports drag start / end (or exit completion) here.
    func setCardInteractionActive(_ active: Bool) {
        isCardInteractionActive = active
    }

    @discardableResult
    func recordSwipe(item: Item, action: SwipeType) async -> Bool {
        let itemId = item.id
        isCardInteractionActive = false
        // Only advance when the swiped card is still the top of the deck. If the
        // deck was replaced while the card was flying off, advancing would skip
        // a card the user never saw; the swipe itself is still recorded.
        if currentIndex < items.count, items[currentIndex].id == itemId {
            currentIndex += 1
            lastSwipe = (item, action)
        }
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

    /// Whether the last swipe can be taken back (its card is still right
    /// behind the current top card).
    var canUndoLastSwipe: Bool {
        guard let lastSwipe, currentIndex > 0, currentIndex <= items.count else { return false }
        return items[currentIndex - 1].id == lastSwipe.item.id
    }

    /// Brings the last swiped card back to the top of the deck. If the swipe
    /// has not been uploaded yet it is simply dropped from the local queue. If
    /// it already reached the server there is no per-item delete endpoint, so
    /// it stays recorded until the user swipes the restored card again — which
    /// overwrites it (POST /swipes is an upsert, last action wins).
    func undoLastSwipe() {
        guard canUndoLastSwipe, let swipe = lastSwipe else { return }
        lastSwipe = nil
        currentIndex -= 1
        persistFeedWarmCache()
        let itemId = swipe.item.id
        Task { await PendingSwipeQueue.shared.remove(itemId: itemId) }
    }

    func loadMoreIfNeeded() async {
        let remaining = items.count - currentIndex
        guard remaining < Self.loadMoreThreshold else { return }
        guard !isFeedExhausted else { return }
        guard !isLoadingMore, !isLoading else { return }
        let generation = feedGeneration
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }
        do {
            let result = try await fetchFeed(excludingIds: exclusionIdsForNextPage())
            // Filters changed (or the deck was reloaded) while this page was in
            // flight: its cards belong to the old query.
            guard generation == feedGeneration else { return }
            appendFeedPage(result.items, matches: result.matches)
            isFeedExhausted = !result.hasMore
            persistFeedWarmCache()
            scheduleFeedImagePrefetch()
        } catch {
            guard generation == feedGeneration, !error.isCancellation else { return }
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
    @ObservationIgnored private var lastExhaustionRecoveryAt: Date?
    private(set) var isRecoveringFeed = false

    func attemptExhaustionRecovery() async {
        guard isFeedExhausted, !hasMoreItems, !isRecoveringFeed, !isLoading else { return }
        if let last = lastExhaustionRecoveryAt, Date().timeIntervalSince(last) < 30 { return }
        lastExhaustionRecoveryAt = Date()
        isRecoveringFeed = true
        defer { isRecoveringFeed = false }
        let generation = feedGeneration
        do {
            let result = try await fetchFeed()
            guard generation == feedGeneration else { return }
            if !result.items.isEmpty {
                items = result.items
                replaceMatches(with: result.matches, retainingIds: Set(result.items.map(\.id)))
                currentIndex = 0
                lastSwipe = nil
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

    // MARK: - Image prefetch

    /// Warms the upcoming window with ONE prefetcher: the previous pass is
    /// cancelled, URLs already in memory are skipped, and a card's fallback
    /// (original photo) is only fetched when its primary (background-removed)
    /// image fails — the same order `CachedAsyncImage` uses — instead of always
    /// downloading both.
    private func scheduleFeedImagePrefetch() {
        let end = min(currentIndex + imagePrefetchWindow, items.count)
        guard currentIndex < end else { return }
        var pairs: [(primary: URL, fallback: URL?)] = []
        var seen = Set<String>()
        for item in items[currentIndex..<end] {
            guard let pair = item.imageUrlPairs.first, let primary = URL(string: pair.primary) else { continue }
            guard seen.insert(primary.absoluteString).inserted else { continue }
            if ImageCacheService.shared.image(for: primary) != nil { continue }
            pairs.append((primary, pair.fallback.flatMap { URL(string: $0) }))
        }
        imagePrefetchTask?.cancel()
        guard !pairs.isEmpty else { return }
        imagePrefetchTask = Task {
            let chunkSize = 4
            var index = 0
            while index < pairs.count, !Task.isCancelled {
                let chunk = pairs[index..<min(index + chunkSize, pairs.count)]
                await withTaskGroup(of: Void.self) { group in
                    for pair in chunk {
                        group.addTask {
                            if await ImageCacheService.shared.loadImage(from: pair.primary) == nil,
                               let fallback = pair.fallback {
                                _ = await ImageCacheService.shared.loadImage(from: fallback)
                            }
                        }
                    }
                }
                index += chunkSize
            }
        }
    }
}
