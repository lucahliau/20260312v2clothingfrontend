import Foundation
import Observation

@Observable
final class SwipeHistoryViewModel {
    var records: [SwipeRecord] = []
    var isLoading = false
    var errorMessage: String?

    private(set) var lastHistoryLoadAt: Date?

    /// True when data was loaded with a small page size and should be upgraded to full when the user opens History.
    private(set) var isPreviewOnly = false

    private let staleDuration: TimeInterval = 90

    private static let previewLimit = 30
    private static let fullLimit = 100

    private var initialLoadTask: Task<Void, Never>?

    /// Sections in display order: Love, Like, Neutral, Dislike
    private static let sectionOrder: [SwipeType] = [.LOVE, .LIKE, .NEUTRAL, .DISLIKE]

    /// Records grouped by action in display order
    var recordsBySection: [(SwipeType, [SwipeRecord])] {
        var grouped: [SwipeType: [SwipeRecord]] = [:]
        for action in Self.sectionOrder {
            grouped[action] = []
        }
        for record in records {
            grouped[record.action, default: []].append(record)
        }
        return Self.sectionOrder.compactMap { action in
            let list = grouped[action] ?? []
            return list.isEmpty ? nil : (action, list)
        }
    }

    init() {
        if let warm = SwipeWarmCache.load() {
            records = warm.records
            isPreviewOnly = warm.isPreviewOnly
            lastHistoryLoadAt = warm.savedAt
            // This init runs during MainTabView construction (inside the first
            // frame) — warm images asynchronously, never on the launch frame.
            let urls = Self.urlsForPrefetch(from: warm.records, max: 24)
            Task(priority: .utility) {
                await ImageCacheService.shared.warmMemoryFromDisk(urls: urls)
            }
            Task { await self.applyRenderableRecordFilter() }
        }
    }

    private func applyRenderableRecordFilter() async {
        let filtered = await ItemImageDisplayability.filterSwipeRecords(records)
        await MainActor.run {
            self.records = filtered
            self.persistSwipeWarmCache()
        }
    }

    /// Session warm-up: small first page when there is no disk snapshot and no in-flight data.
    func loadPreviewIfNeeded() async {
        guard lastHistoryLoadAt == nil, records.isEmpty else { return }
        await performInitialLoad(preferPreview: true)
    }

    func loadIfNeeded() async {
        if isPreviewOnly {
            await loadFullHistory()
            return
        }
        if lastHistoryLoadAt != nil {
            await refreshHistoryIfStale()
            return
        }
        await performInitialLoad(preferPreview: false)
    }

    private func performInitialLoad(preferPreview: Bool) async {
        if let existing = initialLoadTask {
            await existing.value
            if !preferPreview, isPreviewOnly {
                await loadFullHistory()
            }
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            if preferPreview {
                await self.loadHistoryPreview()
            } else {
                await self.loadHistoryInitialFull()
            }
        }
        initialLoadTask = task
        await task.value
        initialLoadTask = nil
    }

    private func loadHistoryPreview() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let raw = try await SwipeService.fetchSwipeHistory(limit: Self.previewLimit)
            records = await ItemImageDisplayability.filterSwipeRecords(raw)
            isPreviewOnly = true
            lastHistoryLoadAt = Date()
            persistSwipeWarmCache()
            prefetchHistoryImages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadHistoryInitialFull() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let raw = try await SwipeService.fetchSwipeHistory(limit: Self.fullLimit)
            records = await ItemImageDisplayability.filterSwipeRecords(raw)
            isPreviewOnly = false
            lastHistoryLoadAt = Date()
            persistSwipeWarmCache()
            prefetchHistoryImages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadFullHistory() async {
        guard isPreviewOnly else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let raw = try await SwipeService.fetchSwipeHistory(limit: Self.fullLimit)
            records = await ItemImageDisplayability.filterSwipeRecords(raw)
            isPreviewOnly = false
            lastHistoryLoadAt = Date()
            persistSwipeWarmCache()
            prefetchHistoryImages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshHistoryIfStale() async {
        guard let last = lastHistoryLoadAt else {
            await refreshHistorySilently()
            return
        }
        if Date().timeIntervalSince(last) < staleDuration { return }
        await refreshHistorySilently()
    }

    private func refreshHistorySilently() async {
        do {
            let limit = isPreviewOnly ? Self.previewLimit : Self.fullLimit
            let raw = try await SwipeService.fetchSwipeHistory(limit: limit)
            records = await ItemImageDisplayability.filterSwipeRecords(raw)
            lastHistoryLoadAt = Date()
            persistSwipeWarmCache()
            prefetchHistoryImages()
        } catch {
            // Keep existing records
        }
    }

    func updateRecord(_ record: SwipeRecord, newAction: SwipeType) async {
        do {
            let updated = try await SwipeService.updateSwipe(swipeId: record.id, action: newAction)
            if let idx = records.firstIndex(where: { $0.id == record.id }) {
                let merged = SwipeRecord(
                    id: updated.id,
                    userId: updated.userId,
                    itemId: updated.itemId,
                    action: updated.action,
                    item: updated.item ?? record.item,
                    createdAt: updated.createdAt
                )
                records[idx] = merged
            }
            lastHistoryLoadAt = Date()
            persistSwipeWarmCache()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistSwipeWarmCache() {
        SwipeWarmCache.save(records: records, isPreviewOnly: isPreviewOnly)
    }

    private func prefetchHistoryImages() {
        let urls = Self.urlsForPrefetch(from: records, max: 32)
        for url in urls {
            ImageCacheService.shared.preload(from: url)
        }
        Task.detached(priority: .utility) {
            await Self.prefetchImagesAggressively(urls: urls)
        }
    }

    private static func urlsForPrefetch(from records: [SwipeRecord], max: Int) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        for record in records {
            guard let item = record.item else { continue }
            if let u = item.firstOriginalImageURL, seen.insert(u.absoluteString).inserted {
                urls.append(u)
                if urls.count >= max { break }
            }
            if let pair = item.imageUrlPairs.first, let u = URL(string: pair.primary), seen.insert(u.absoluteString).inserted {
                urls.append(u)
                if urls.count >= max { break }
            }
        }
        return urls
    }

    private static func prefetchImagesAggressively(urls: [URL]) async {
        let chunkSize = 5
        var i = urls.startIndex
        while i < urls.endIndex {
            let j = urls.index(i, offsetBy: chunkSize, limitedBy: urls.endIndex) ?? urls.endIndex
            await withTaskGroup(of: Void.self) { group in
                var k = i
                while k < j {
                    let url = urls[k]
                    group.addTask {
                        _ = await ImageCacheService.shared.loadImage(from: url)
                    }
                    k = urls.index(after: k)
                }
            }
            i = j
        }
    }
}
