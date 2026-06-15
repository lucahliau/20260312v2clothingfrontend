import CryptoKit
import Foundation
import ImageIO
import OSLog
import UIKit

final class ImageCacheService {
    static let shared = ImageCacheService()

    private nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clothing", category: "ImageCache")

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session = URLSession.shared
    private var loadTasks: [URL: Task<(UIImage?, Int?), Never>] = [:]
    private let lock = NSLock()

    private let diskCacheDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        memoryCache.countLimit = 200
        // Decoded feed cards are ~5 MB each at 1300px, and every feed item warms
        // TWO urls (background-removed primary + original fallback). The old
        // 100 MB ceiling held only ~20 bitmaps — less than the 12-card look-ahead
        // window (×2 urls ≈ 24), so warming the window evicted the very next card
        // and it ghosted/flashed on reveal. 200 MB comfortably holds the window
        // plus the live deck and a recent-history buffer without self-eviction.
        // NSCache still purges everything under real memory pressure as a safety
        // valve, and the mounted deck cards retain their own bitmaps regardless.
        memoryCache.totalCostLimit = 200 * 1024 * 1024 // 200 MB
    }

    /// Returns cached image from memory only (sync).
    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    /// Loads image from memory, disk, or network; deduplicates concurrent loads per URL.
    func loadImage(from url: URL) async -> UIImage? {
        let (image, _) = await loadImageWithStatus(from: url)
        return image
    }

    /// Same as `loadImage`, but returns the HTTP status code from the **last** failed network response when no image is produced (decode failure or non-success status).
    func loadImageWithStatus(from url: URL) async -> (UIImage?, Int?) {
        if let cached = memoryCache.object(forKey: url.absoluteString as NSString) {
            return (cached, nil)
        }

        lock.lock()
        if let existingTask = loadTasks[url] {
            lock.unlock()
            return await existingTask.value
        }
        let task = Task<(UIImage?, Int?), Never> {
            await performLoad(from: url)
        }
        loadTasks[url] = task
        lock.unlock()

        let result = await task.value

        lock.lock()
        loadTasks[url] = nil
        lock.unlock()

        return result
    }

    /// Drops memory and disk entries for a URL (e.g. after a confirmed bad response).
    func removeCachedEntry(for url: URL) {
        memoryCache.removeObject(forKey: url.absoluteString as NSString)
        let fileURL = diskFileURL(for: url)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func preload(from url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = await self?.loadImage(from: url)
        }
    }

    /// Loads images from existing disk files into memory only. Skips URLs already in memory.
    /// File I/O and decoding run off the main actor so warm-path callers (first feed cards,
    /// history preview) never stall the launch frame.
    func warmMemoryFromDisk(urls: [URL], maxUrls: Int = 24) async {
        var pairs: [(key: String, file: URL)] = []
        var seen = Set<String>()
        for url in urls {
            if pairs.count >= maxUrls { break }
            guard seen.insert(url.absoluteString).inserted else { continue }
            if memoryCache.object(forKey: url.absoluteString as NSString) != nil { continue }
            pairs.append((url.absoluteString, diskFileURL(for: url)))
        }
        guard !pairs.isEmpty else { return }
        let decoded = await Task.detached(priority: .userInitiated) {
            var out: [(String, UIImage)] = []
            for (key, fileURL) in pairs {
                guard FileManager.default.fileExists(atPath: fileURL.path),
                      let data = try? Data(contentsOf: fileURL),
                      let image = Self.decodeDownsampled(data) else { continue }
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

    /// NSCache cost in decoded-bitmap bytes, so the 100 MB limit tracks real memory
    /// (compressed `data.count` undercounts by 10-20x).
    nonisolated static func decodedCost(of image: UIImage) -> Int {
        if let cg = image.cgImage { return cg.bytesPerRow * cg.height }
        return Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    private func performLoad(from url: URL) async -> (UIImage?, Int?) {
        let key = url.absoluteString as NSString

        if let (_, fromDisk) = await loadFromDisk(url: url) {
            memoryCache.setObject(fromDisk, forKey: key, cost: Self.decodedCost(of: fromDisk))
            return (fromDisk, nil)
        }

        do {
            let (data, response) = try await session.data(from: url)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? -1
            let mime = http?.mimeType ?? "(nil)"

            if let http, !(200 ... 299).contains(http.statusCode) {
                Self.log.error("HTTP non-success for image url=\(url.absoluteString, privacy: .public) status=\(status) bytes=\(data.count) mime=\(mime, privacy: .public)")
                return (nil, status)
            }

            // Decode (downsampled) off the main actor — this class is MainActor-isolated
            // by the project's default isolation, so an inline decode would block UI.
            let decoded = await Task.detached(priority: .userInitiated) {
                Self.decodeDownsampled(data)
            }.value
            guard let image = decoded else {
                Self.log.error(
                    "UIImage decode failed after fetch url=\(url.absoluteString, privacy: .public) status=\(status) bytes=\(data.count) mime=\(mime, privacy: .public) headHex=\(Self.hexPrefix(data, maxBytes: 24), privacy: .public)"
                )
                return (nil, status)
            }
            memoryCache.setObject(image, forKey: key, cost: Self.decodedCost(of: image))
            await writeToDisk(data: data, for: url)
            return (image, nil)
        } catch {
            if let urlError = error as? URLError {
                Self.log.error(
                    "Network fetch failed url=\(url.absoluteString, privacy: .public) URLError.code=\(urlError.code.rawValue) \(urlError.localizedDescription, privacy: .public)"
                )
            } else {
                Self.log.error("Network fetch failed url=\(url.absoluteString, privacy: .public) \(error.localizedDescription, privacy: .public)")
            }
            return (nil, nil)
        }
    }

    private func loadFromDisk(url: URL) async -> (Data, UIImage)? {
        let fileURL = diskFileURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return await Task.detached(priority: .utility) {
            let path = fileURL.path
            do {
                let data = try Data(contentsOf: fileURL)
                guard let image = Self.decodeDownsampled(data) else {
                    Self.log.error(
                        "Disk cache UIImage decode failed path=\(path, privacy: .public) bytes=\(data.count) headHex=\(Self.hexPrefix(data, maxBytes: 24), privacy: .public)"
                    )
                    return nil
                }
                return (data, image)
            } catch {
                Self.log.error("Disk cache read failed path=\(path, privacy: .public) \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    private func writeToDisk(data: Data, for url: URL) async {
        let fileURL = diskFileURL(for: url)
        await Task.detached(priority: .utility) {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Self.log.error("Disk cache write failed path=\(fileURL.path, privacy: .public) \(error.localizedDescription, privacy: .public)")
            }
        }.value
    }

    private nonisolated static func hexPrefix(_ data: Data, maxBytes: Int) -> String {
        let n = min(maxBytes, data.count)
        guard n > 0 else { return "" }
        return data.prefix(n).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func diskFileURL(for url: URL) -> URL {
        diskCacheDirectory.appendingPathComponent(sha256(url.absoluteString)).appendingPathExtension("img")
    }

    private func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
