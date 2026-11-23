import CryptoKit
import Foundation
import ImageIO
import OSLog
import UIKit

/// Memory + disk image cache.
///
/// - Disk: original bytes under `Caches/ImageCache` (purgeable by iOS, not
///   backed up), capped at `diskCapacityBytes` with least-recently-used
///   eviction; pruned in the background at launch.
/// - Memory: decoded bitmaps in an `NSCache`. Callers that only need a small
///   picture (grid cells, rails) pass `maxPixelSize: ImageCacheService.thumbnailPixelSize`
///   and get an ImageIO-downsampled bitmap (~1.4 MB instead of ~6 MB); the
///   swipe card and item detail omit it and get the full-size decode.
///
/// MainActor-isolated by the project's default isolation, so the dictionaries
/// below need no locking; file I/O and decoding hop to detached tasks.
final class ImageCacheService {
    static let shared = ImageCacheService()

    /// Long-edge pixel size for grid / rail thumbnails (covers a ~200 pt cell at 3x).
    nonisolated static let thumbnailPixelSize: CGFloat = 600
    /// Long-edge pixel size for full-bleed images (swipe card, detail photos).
    nonisolated static let fullPixelSize: CGFloat = 1300
    /// Disk cache ceiling; pruning trims to 90% of this.
    private nonisolated static let diskCapacityBytes: Int64 = 500 * 1024 * 1024

    private nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clothing", category: "ImageCache")

    private let memoryCache = NSCache<NSString, UIImage>()
    /// Own session: a stalled image fails in 20 s instead of URLSession.shared's
    /// 60 s, and URLCache is off — this class already stores the bytes on disk,
    /// so the shared URLCache would only keep a second copy.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    /// In-flight decodes, keyed by memory-cache key (url + size variant).
    private var loadTasks: [String: Task<(UIImage?, Int?), Never>] = [:]
    /// In-flight downloads, keyed by URL — a thumbnail and a full-size request
    /// for the same URL share one download.
    private var downloadTasks: [URL: Task<(Data?, Int?), Never>] = [:]

    private nonisolated static let diskCacheDirectory: URL = {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let dir = caches.appendingPathComponent("ImageCache", isDirectory: true)
        // Pre-2026-11 builds kept this in Application Support (backed up, never
        // evicted). Adopt it once with a rename (same volume, instant); if the
        // new directory already exists the old one is deleted during pruning.
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let legacy = support.appendingPathComponent("ImageCache", isDirectory: true)
            if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: caches, withIntermediateDirectories: true)
                try? fm.moveItem(at: legacy, to: dir)
            }
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        memoryCache.countLimit = 300
        // Decoded feed cards are ~5 MB each at 1300px and the look-ahead window
        // keeps ~12 of them warm (plus the live deck); thumbnails are ~1.4 MB.
        // NSCache still purges everything under real memory pressure, and
        // mounted views retain their own bitmaps regardless.
        memoryCache.totalCostLimit = 200 * 1024 * 1024 // 200 MB
        Task.detached(priority: .background) {
            Self.pruneDiskCache()
        }
    }

    // MARK: - Keys

    /// `nil` / anything at or above full size → the full-size variant.
    private nonisolated static func normalizedPixelSize(_ maxPixelSize: CGFloat?) -> CGFloat {
        guard let maxPixelSize, maxPixelSize < fullPixelSize else { return fullPixelSize }
        return maxPixelSize <= thumbnailPixelSize ? thumbnailPixelSize : fullPixelSize
    }

    private nonisolated static func memoryKey(_ url: URL, pixelSize: CGFloat) -> String {
        pixelSize >= fullPixelSize ? url.absoluteString : "\(url.absoluteString)#\(Int(pixelSize))"
    }

    // MARK: - Lookup

    /// Returns cached image from memory only (sync). A thumbnail request is
    /// also satisfied by a full-size bitmap that is already in memory.
    func image(for url: URL, maxPixelSize: CGFloat? = nil) -> UIImage? {
        let px = Self.normalizedPixelSize(maxPixelSize)
        if let hit = memoryCache.object(forKey: Self.memoryKey(url, pixelSize: px) as NSString) {
            return hit
        }
        if px < Self.fullPixelSize {
            return memoryCache.object(forKey: url.absoluteString as NSString)
        }
        return nil
    }

    /// Loads image from memory, disk, or network; deduplicates concurrent loads per URL.
    func loadImage(from url: URL, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        let (image, _) = await loadImageWithStatus(from: url, maxPixelSize: maxPixelSize)
        return image
    }

    /// Same as `loadImage`, but returns the HTTP status code from the **last** failed network response when no image is produced (decode failure or non-success status).
    func loadImageWithStatus(from url: URL, maxPixelSize: CGFloat? = nil) async -> (UIImage?, Int?) {
        if let cached = image(for: url, maxPixelSize: maxPixelSize) {
            return (cached, nil)
        }
        let px = Self.normalizedPixelSize(maxPixelSize)
        let key = Self.memoryKey(url, pixelSize: px)
        if let existingTask = loadTasks[key] {
            return await existingTask.value
        }
        let task = Task<(UIImage?, Int?), Never> {
            await performLoad(from: url, pixelSize: px, key: key)
        }
        loadTasks[key] = task
        let result = await task.value
        loadTasks[key] = nil
        return result
    }

    /// Drops memory and disk entries for a URL (e.g. after a confirmed bad response).
    func removeCachedEntry(for url: URL) {
        memoryCache.removeObject(forKey: url.absoluteString as NSString)
        memoryCache.removeObject(forKey: Self.memoryKey(url, pixelSize: Self.thumbnailPixelSize) as NSString)
        let fileURL = Self.diskFileURL(for: url)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func preload(from url: URL, maxPixelSize: CGFloat? = nil) {
        Task(priority: .utility) { [weak self] in
            _ = await self?.loadImage(from: url, maxPixelSize: maxPixelSize)
        }
    }

    /// Loads images from existing disk files into memory only. Skips URLs already in memory.
    /// File I/O and decoding run off the main actor so warm-path callers (first feed cards,
    /// history preview) never stall the launch frame.
    func warmMemoryFromDisk(urls: [URL], maxUrls: Int = 24, maxPixelSize: CGFloat? = nil) async {
        let px = Self.normalizedPixelSize(maxPixelSize)
        var pairs: [(key: String, file: URL)] = []
        var seen = Set<String>()
        for url in urls {
            if pairs.count >= maxUrls { break }
            guard seen.insert(url.absoluteString).inserted else { continue }
            if image(for: url, maxPixelSize: px) != nil { continue }
            pairs.append((Self.memoryKey(url, pixelSize: px), Self.diskFileURL(for: url)))
        }
        guard !pairs.isEmpty else { return }
        let decoded = await Task.detached(priority: .userInitiated) {
            var out: [(String, UIImage)] = []
            for (key, fileURL) in pairs {
                guard FileManager.default.fileExists(atPath: fileURL.path),
                      let data = try? Data(contentsOf: fileURL),
                      let image = Self.decodeDownsampled(data, maxPixelSize: px) else { continue }
                Self.touch(fileURL)
                out.append((key, image))
            }
            return out
        }.value
        for (key, image) in decoded {
            memoryCache.setObject(image, forKey: key as NSString, cost: Self.decodedCost(of: image))
        }
    }

    /// Decodes image data downsampled to at most `maxPixelSize` on the long edge.
    /// Catalog originals are often 2000px+ — a full decode is a ~20MB bitmap that the
    /// GPU then composites under the glass tab bar; at 1300px (full-bleed card on a
    /// 3x 390pt screen) it's ~5MB and ImageIO's thumbnail path decodes much faster.
    /// Preserves alpha (the `-nobg.png` variants).
    nonisolated static func decodeDownsampled(_ data: Data, maxPixelSize: CGFloat = 1300) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            // Formats ImageIO can't thumbnail still get a full decode.
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    /// NSCache cost in decoded-bitmap bytes, so the limit tracks real memory
    /// (compressed `data.count` undercounts by 10-20x).
    nonisolated static func decodedCost(of image: UIImage) -> Int {
        if let cg = image.cgImage { return cg.bytesPerRow * cg.height }
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    // MARK: - Loading

    private func performLoad(from url: URL, pixelSize: CGFloat, key: String) async -> (UIImage?, Int?) {
        if let fromDisk = await loadFromDisk(url: url, pixelSize: pixelSize) {
            memoryCache.setObject(fromDisk, forKey: key as NSString, cost: Self.decodedCost(of: fromDisk))
            return (fromDisk, nil)
        }

        let (data, status) = await download(url)
        guard let data else { return (nil, status) }

        // Decode (downsampled) off the main actor — this class is MainActor-isolated
        // by the project's default isolation, so an inline decode would block UI.
        let decoded = await Task.detached(priority: .userInitiated) {
            Self.decodeDownsampled(data, maxPixelSize: pixelSize)
        }.value
        guard let image = decoded else {
            Self.log.error(
                "UIImage decode failed after fetch url=\(url.absoluteString, privacy: .public) bytes=\(data.count) headHex=\(Self.hexPrefix(data, maxBytes: 24), privacy: .public)"
            )
            return (nil, status ?? 200)
        }
        memoryCache.setObject(image, forKey: key as NSString, cost: Self.decodedCost(of: image))
        return (image, nil)
    }

    /// Downloads the original bytes once per URL (shared by concurrent size
    /// variants) and writes them to disk. Returns `(nil, status)` on an HTTP
    /// error and `(nil, nil)` on a transport failure.
    private func download(_ url: URL) async -> (Data?, Int?) {
        if let existing = downloadTasks[url] {
            return await existing.value
        }
        let session = session
        let task = Task<(Data?, Int?), Never> {
            do {
                let (data, response) = try await session.data(from: url)
                let http = response as? HTTPURLResponse
                if let http, !(200 ... 299).contains(http.statusCode) {
                    Self.log.error("HTTP non-success for image url=\(url.absoluteString, privacy: .public) status=\(http.statusCode) bytes=\(data.count)")
                    return (nil, http.statusCode)
                }
                let fileURL = Self.diskFileURL(for: url)
                Task.detached(priority: .utility) {
                    do {
                        try data.write(to: fileURL, options: .atomic)
                    } catch {
                        Self.log.error("Disk cache write failed path=\(fileURL.path, privacy: .public) \(error.localizedDescription, privacy: .public)")
                    }
                }
                return (data, http?.statusCode)
            } catch {
                Self.log.error("Network fetch failed url=\(url.absoluteString, privacy: .public) \(error.localizedDescription, privacy: .public)")
                return (nil, nil)
            }
        }
        downloadTasks[url] = task
        let result = await task.value
        downloadTasks[url] = nil
        return result
    }

    private func loadFromDisk(url: URL, pixelSize: CGFloat) async -> UIImage? {
        let fileURL = Self.diskFileURL(for: url)
        return await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let path = fileURL.path
            do {
                let data = try Data(contentsOf: fileURL)
                guard let image = Self.decodeDownsampled(data, maxPixelSize: pixelSize) else {
                    Self.log.error(
                        "Disk cache UIImage decode failed path=\(path, privacy: .public) bytes=\(data.count) headHex=\(Self.hexPrefix(data, maxBytes: 24), privacy: .public)"
                    )
                    // A file that can't decode would shadow the network copy forever.
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }
                Self.touch(fileURL)
                return image
            } catch {
                Self.log.error("Disk cache read failed path=\(path, privacy: .public) \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    // MARK: - Disk housekeeping

    /// Marks a file as recently used (LRU eviction orders by modification date).
    private nonisolated static func touch(_ fileURL: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    /// Deletes least-recently-used files until the cache is under 90% of the
    /// cap, and removes a leftover pre-migration directory. Runs off the main
    /// actor at launch.
    nonisolated static func pruneDiskCache() {
        let fm = FileManager.default
        let dir = diskCacheDirectory
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let legacy = support.appendingPathComponent("ImageCache", isDirectory: true)
            if fm.fileExists(atPath: legacy.path) {
                try? fm.removeItem(at: legacy)
            }
        }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = Int64(values.fileSize ?? 0)
            total += size
            entries.append((url, size, values.contentModificationDate ?? .distantPast))
        }
        guard total > diskCapacityBytes else { return }
        let target = diskCapacityBytes / 10 * 9
        var removed = 0
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if total <= target { break }
            if (try? fm.removeItem(at: entry.url)) != nil {
                total -= entry.size
                removed += 1
            }
        }
        log.info("Disk cache pruned: removed \(removed) files, now \(total / 1_048_576) MB")
    }

    private nonisolated static func hexPrefix(_ data: Data, maxBytes: Int) -> String {
        let n = min(maxBytes, data.count)
        guard n > 0 else { return "" }
        return data.prefix(n).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private nonisolated static func diskFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return diskCacheDirectory.appendingPathComponent(name).appendingPathExtension("img")
    }
}
