import CryptoKit
import Foundation
import UIKit

final class ImageCacheService {
    static let shared = ImageCacheService()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let session = URLSession.shared
    private var loadTasks: [URL: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private let diskCacheDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    /// Returns cached image from memory only (sync).
    func image(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url.absoluteString as NSString)
    }

    /// Loads image from memory, disk, or network; deduplicates concurrent loads per URL.
    func loadImage(from url: URL) async -> UIImage? {
        if let cached = memoryCache.object(forKey: url.absoluteString as NSString) {
            return cached
        }

        lock.lock()
        if let existingTask = loadTasks[url] {
            lock.unlock()
            return await existingTask.value
        }
        let task = Task<UIImage?, Never> {
            await performLoad(from: url)
        }
        loadTasks[url] = task
        lock.unlock()

        let image = await task.value

        lock.lock()
        loadTasks[url] = nil
        lock.unlock()

        return image
    }

    func preload(from url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            _ = await self?.loadImage(from: url)
        }
    }

    /// Loads images from existing disk files into memory only. Skips URLs already in memory.
    /// Uses synchronous I/O on the caller thread; intended for warm-path URL lists (e.g. first feed cards).
    func warmMemoryFromDisk(urls: [URL], maxUrls: Int = 24) {
        var seen = Set<String>()
        var n = 0
        for url in urls {
            if n >= maxUrls { break }
            guard seen.insert(url.absoluteString).inserted else { continue }
            if memoryCache.object(forKey: url.absoluteString as NSString) != nil { continue }
            let fileURL = diskFileURL(for: url)
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: data) else { continue }
            memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: data.count)
            n += 1
        }
    }

    private func performLoad(from url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        if let (data, fromDisk) = await loadFromDisk(url: url) {
            memoryCache.setObject(fromDisk, forKey: key, cost: data.count)
            return fromDisk
        }

        do {
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: key, cost: data.count)
            await writeToDisk(data: data, for: url)
            return image
        } catch {
            return nil
        }
    }

    private func loadFromDisk(url: URL) async -> (Data, UIImage)? {
        let fileURL = diskFileURL(for: url)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else { return nil }
            return (data, image)
        }.value
    }

    private func writeToDisk(data: Data, for url: URL) async {
        let fileURL = diskFileURL(for: url)
        await Task.detached(priority: .utility) {
            try? data.write(to: fileURL, options: .atomic)
        }.value
    }

    private func diskFileURL(for url: URL) -> URL {
        diskCacheDirectory.appendingPathComponent(sha256(url.absoluteString)).appendingPathExtension("img")
    }

    private func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
