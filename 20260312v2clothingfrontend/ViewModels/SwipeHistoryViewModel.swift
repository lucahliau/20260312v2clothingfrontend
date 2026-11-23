import Foundation
import Observation

/// Owns the user's swipe data in two independent lists:
/// - `likedRecords`: every LOVE/LIKE swipe (the Wardrobe). Loaded in full by
///   paging `/swipes/history?action=LOVE,LIKE`, so search/sort/filter work over
///   the whole set. Warm-cached on disk for instant cold start.
/// - `records`: the mixed History screen (all actions), paged on demand.
///
/// Records are shown as soon as they arrive — image loading never gates or
/// filters either list (tiles fall back to a placeholder).
@Observable
final class SwipeHistoryViewModel {
    // MARK: - Wardrobe (liked + loved)

    private(set) var likedRecords: [SwipeRecord] = []
    private(set) var isLoadingLiked = false
    /// Set when the last liked-items load failed; cleared by the next success.
    var likedErrorMessage: String?
    private(set) var likedLoadedAt: Date?

    // MARK: - History (all actions)

    private(set) var records: [SwipeRecord] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMoreHistory = false
    /// Server-side total across all pages (for the "Showing X of Y" footer).
    private(set) var historyTotal: Int?
    /// Failures from History paging and from swipe edits (either screen).
    var errorMessage: String?

    private var historyLoadedAt: Date?
    private var historyNextPage = 1

    private let staleDuration: TimeInterval = 90

    /// Backend caps `/swipes/history` at 100 rows per page.
    private static let likedPageSize = 100
    private static let historyPageSize = 50
    /// Runaway guard for the liked pager (200 pages = 20,000 likes).
    private static let maxLikedPages = 200
    private static let likedActions: [SwipeType] = [.LOVE, .LIKE]

    private var likedLoadTask: Task<Void, Never>?
    /// A reload was requested while one was already running — run once more
    /// afterwards so the latest server state always wins.
    private var likedReloadQueued = false

    private var changeRefreshTask: Task<Void, Never>?
    /// A like the list doesn't hold yet is waiting on the server. Starts
    /// `true` so swipes queued by a previous session are picked up by the
    /// first flush. Keeps dislike-only batches from triggering refetches.
    private var hasUnfetchedLike = true

    /// Sections in display order: Love, Like, Neutral, Dislike
    private static let sectionOrder: [SwipeType] = [.LOVE, .LIKE, .NEUTRAL, .DISLIKE]

    /// History records grouped by action in display order
    var recordsBySection: [(SwipeType, [SwipeRecord])] {
        var grouped: [SwipeType: [SwipeRecord]] = [:]
        for record in records {
            grouped[record.action, default: []].append(record)
        }
        return Self.sectionOrder.compactMap { action in
            let list = grouped[action] ?? []
            return list.isEmpty ? nil : (action, list)
        }
    }

    static func isLiked(_ action: SwipeType) -> Bool {
        action == .LOVE || action == .LIKE
    }

    init() {
        if let warm = SwipeWarmCache.load() {
            likedRecords = warm.records
            likedLoadedAt = warm.savedAt
            // This init runs during MainTabView construction (inside the first
            // frame) — warm images asynchronously, never on the launch frame.
            let urls = Self.urlsForPrefetch(from: warm.records, max: 24)
            Task(priority: .utility) {
                await ImageCacheService.shared.warmMemoryFromDisk(urls: urls)
            }
        }
        observeSwipeChanges()
    }

    // MARK: - Live updates

    /// Swipes recorded anywhere (feed, Explore, item detail, offline queue)
    /// are announced via `.swipesDidChange`, so the Wardrobe never waits for
    /// the staleness window. The observer lives as long as the process; it
    /// only holds `self` weakly.
    private func observeSwipeChanges() {
        NotificationCenter.default.addObserver(
            forName: .swipesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let itemId = note.userInfo?[SwipeChange.itemIdKey] as? String
            let action = (note.userInfo?[SwipeChange.actionKey] as? String).flatMap(SwipeType.init(rawValue:))
            let synced = (note.userInfo?[SwipeChange.syncedKey] as? Bool) ?? false
            Task { @MainActor [weak self] in
                self?.handleSwipeChange(itemId: itemId, action: action, synced: synced)
            }
        }
    }

    private func handleSwipeChange(itemId: String?, action: SwipeType?, synced: Bool) {
        // What can be applied locally is applied at once: an un-like leaves
        // the Wardrobe, a like<->love change updates in place.
        if let itemId, let action {
            if let idx = likedRecords.firstIndex(where: { $0.itemId == itemId }) {
                let existing = likedRecords[idx]
                if !Self.isLiked(action) {
                    likedRecords.remove(at: idx)
                    persistLikedIfComplete()
                } else if existing.action != action {
                    likedRecords[idx] = SwipeRecord(
                        id: existing.id,
                        userId: existing.userId,
                        itemId: existing.itemId,
                        action: action,
                        item: existing.item,
                        createdAt: existing.createdAt
                    )
                    persistLikedIfComplete()
                }
            } else if Self.isLiked(action) {
                hasUnfetchedLike = true
            }
        }
        // A brand-new like needs its record (id + embedded item) from the
        // server, which is only there once the swipe has synced.
        guard synced else { return }
        historyLoadedAt = nil
        guard hasUnfetchedLike else { return }
        changeRefreshTask?.cancel()
        changeRefreshTask = Task { [weak self] in
            // Coalesce bursts (a batch flush plus direct posts).
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.reloadLiked()
        }
    }

    // MARK: - Liked loading

    /// Wardrobe appearance: load when never loaded, after a failure, or when
    /// the snapshot is older than `staleDuration`.
    func loadLikedIfNeeded() async {
        if likedErrorMessage == nil,
           let at = likedLoadedAt,
           Date().timeIntervalSince(at) < staleDuration {
            return
        }
        await reloadLiked()
    }

    /// Fetches every liked/loved swipe (all pages). Safe to call repeatedly:
    /// concurrent callers share one in-flight load, plus one follow-up pass.
    func reloadLiked() async {
        if let running = likedLoadTask {
            likedReloadQueued = true
            await running.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.likedReloadQueued = false
                self.hasUnfetchedLike = false
                await self.performLikedLoad()
            } while self.likedReloadQueued
            self.likedLoadTask = nil
        }
        likedLoadTask = task
        await task.value
    }

    private func performLikedLoad() async {
        isLoadingLiked = true
        defer { isLoadingLiked = false }
        // With nothing on screen yet, show each page as it lands; otherwise
        // keep the current list until the complete replacement is ready.
        let showProgressively = likedRecords.isEmpty
        do {
            var all: [SwipeRecord] = []
            var seen = Set<String>()
            var page = 1
            while true {
                let response = try await SwipeService.fetchSwipeHistoryPage(
                    page: page,
                    limit: Self.likedPageSize,
                    actions: Self.likedActions
                )
                for record in response.swipes where Self.isLiked(record.action) && seen.insert(record.id).inserted {
                    all.append(record)
                }
                if showProgressively { likedRecords = all }
                let reachedEnd: Bool
                if response.swipes.isEmpty {
                    reachedEnd = true
                } else if let totalPages = response.pagination?.totalPages {
                    reachedEnd = page >= totalPages
                } else {
                    reachedEnd = response.swipes.count < Self.likedPageSize
                }
                if reachedEnd || page >= Self.maxLikedPages { break }
                page += 1
            }
            likedRecords = all
            likedLoadedAt = Date()
            likedErrorMessage = nil
            // Only a complete list is ever persisted.
            SwipeWarmCache.save(records: all)
            prefetchImages(for: all)
        } catch {
            // Keep whatever is on screen (warm cache / previous load); the
            // disk snapshot is left untouched.
            likedErrorMessage = AuthErrorMapper.message(for: error)
        }
    }

    // MARK: - History loading

    /// History screen appearance: first page when empty or stale.
    func loadIfNeeded() async {
        if !records.isEmpty,
           let at = historyLoadedAt,
           Date().timeIntervalSince(at) < staleDuration {
            return
        }
        await reloadHistory()
    }

    func reloadHistory() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await SwipeService.fetchSwipeHistoryPage(page: 1, limit: Self.historyPageSize)
            records = response.swipes
            historyNextPage = 2
            applyHistoryPagination(response, page: 1)
            historyLoadedAt = Date()
            errorMessage = nil
        } catch {
            if records.isEmpty {
                errorMessage = AuthErrorMapper.message(for: error)
            }
        }
    }

    /// Next History page — called as the bottom of the list scrolls into view.
    func loadMoreHistory() async {
        guard hasMoreHistory, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let page = historyNextPage
        do {
            let response = try await SwipeService.fetchSwipeHistoryPage(page: page, limit: Self.historyPageSize)
            let known = Set(records.map(\.id))
            records.append(contentsOf: response.swipes.filter { !known.contains($0.id) })
            historyNextPage = page + 1
            applyHistoryPagination(response, page: page)
        } catch {
            errorMessage = AuthErrorMapper.message(for: error)
        }
    }

    private func applyHistoryPagination(_ response: PaginatedSwipesResponse, page: Int) {
        historyTotal = response.pagination?.total
        if response.swipes.isEmpty {
            hasMoreHistory = false
        } else if let totalPages = response.pagination?.totalPages {
            hasMoreHistory = page < totalPages
        } else {
            hasMoreHistory = response.swipes.count >= Self.historyPageSize
        }
    }

    // MARK: - Edits

    /// Changes an existing swipe's action on the server, then mirrors it into
    /// both lists (a record leaves the Wardrobe when it stops being a like).
    @discardableResult
    func updateRecord(_ record: SwipeRecord, newAction: SwipeType) async -> Bool {
        do {
            let updated = try await SwipeService.updateSwipe(swipeId: record.id, action: newAction)
            let merged = SwipeRecord(
                id: updated.id,
                userId: updated.userId,
                itemId: updated.itemId,
                action: updated.action,
                item: updated.item ?? record.item,
                createdAt: updated.createdAt ?? record.createdAt
            )
            if let idx = records.firstIndex(where: { $0.id == record.id }) {
                records[idx] = merged
            }
            if Self.isLiked(merged.action) {
                if let idx = likedRecords.firstIndex(where: { $0.id == record.id }) {
                    likedRecords[idx] = merged
                } else {
                    likedRecords.insert(merged, at: 0)
                }
            } else {
                likedRecords.removeAll { $0.id == record.id }
            }
            persistLikedIfComplete()
            return true
        } catch {
            errorMessage = AuthErrorMapper.message(for: error)
            return false
        }
    }

    /// Takes an item out of the Wardrobe by downgrading its swipe to NEUTRAL
    /// (the item stays in History and is not re-served by the Feed).
    @discardableResult
    func removeFromWardrobe(_ record: SwipeRecord) async -> Bool {
        await updateRecord(record, newAction: .NEUTRAL)
    }

    /// Local edits are only written to disk on top of a list that came from a
    /// complete load (or the warm cache, itself a complete list) — never on
    /// top of a first load that is still paging in.
    private func persistLikedIfComplete() {
        guard likedLoadedAt != nil else { return }
        SwipeWarmCache.save(records: likedRecords)
    }

    // MARK: - Image prefetch

    private func prefetchImages(for records: [SwipeRecord]) {
        for url in Self.urlsForPrefetch(from: records, max: 24) {
            ImageCacheService.shared.preload(from: url)
        }
    }

    private static func urlsForPrefetch(from records: [SwipeRecord], max: Int) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        for record in records {
            guard let item = record.item else { continue }
            if let pair = item.imageUrlPairs.first, let u = URL(string: pair.primary), seen.insert(u.absoluteString).inserted {
                urls.append(u)
                if urls.count >= max { break }
            }
        }
        return urls
    }
}
