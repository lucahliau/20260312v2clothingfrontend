import CoreGraphics
import UIKit

extension UIImage {
    /// Returns a copy of the image cropped to the bounding box of pixels with alpha greater than `alphaThreshold`.
    /// Returns `self` unchanged if the image has no usable alpha channel or no opaque pixels are found.
    ///
    /// The alpha channel is rasterized into an 8-bit single-channel buffer (downsampled when the image is large)
    /// so a 2-3000 px PNG scans in ~5-15 ms on modern hardware. Call off the main actor.
    nonisolated func trimmedToOpaque(alphaThreshold: UInt8 = 8, maxScanEdge: CGFloat = 512) -> UIImage {
        guard let cgImage else { return self }

        // Downsample for the alpha scan when the source is large; the resulting crop rect is rescaled back.
        let srcWidth = cgImage.width
        let srcHeight = cgImage.height
        let longestEdge = max(srcWidth, srcHeight)
        let scanScale: CGFloat = longestEdge > Int(maxScanEdge)
            ? maxScanEdge / CGFloat(longestEdge)
            : 1.0
        let scanWidth = max(1, Int((CGFloat(srcWidth) * scanScale).rounded()))
        let scanHeight = max(1, Int((CGFloat(srcHeight) * scanScale).rounded()))

        guard let buffer = calloc(scanWidth * scanHeight, MemoryLayout<UInt8>.size) else {
            return self
        }
        defer { free(buffer) }

        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: buffer,
            width: scanWidth,
            height: scanHeight,
            bitsPerComponent: 8,
            bytesPerRow: scanWidth,
            space: space,
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else {
            return self
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: scanWidth, height: scanHeight))

        let bytes = buffer.assumingMemoryBound(to: UInt8.self)

        var minX = scanWidth
        var minY = scanHeight
        var maxX = -1
        var maxY = -1

        for y in 0..<scanHeight {
            let rowStart = y * scanWidth
            for x in 0..<scanWidth {
                if bytes[rowStart + x] > alphaThreshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= 0, maxY >= 0, maxX >= minX, maxY >= minY else {
            return self
        }

        // Convert scan-space bounds back to source-image pixel space.
        let invScale = 1.0 / scanScale
        let cropX = max(0, Int(floor(CGFloat(minX) * invScale)))
        let cropY = max(0, Int(floor(CGFloat(minY) * invScale)))
        let cropMaxX = min(srcWidth, Int(ceil(CGFloat(maxX + 1) * invScale)))
        let cropMaxY = min(srcHeight, Int(ceil(CGFloat(maxY + 1) * invScale)))
        let cropW = max(1, cropMaxX - cropX)
        let cropH = max(1, cropMaxY - cropY)

        // If the trim would remove fewer than 2% of pixels on each axis, skip — not worth the extra UIImage.
        let trimmedFractionW = 1.0 - CGFloat(cropW) / CGFloat(srcWidth)
        let trimmedFractionH = 1.0 - CGFloat(cropH) / CGFloat(srcHeight)
        if trimmedFractionW < 0.02 && trimmedFractionH < 0.02 {
            return self
        }

        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return self }
        return UIImage(cgImage: croppedCG, scale: scale, orientation: imageOrientation)
    }
}

/// Process-wide cache of alpha-trimmed `UIImage`s, keyed by source URL. Keeps trim work to once per URL per session.
final class TrimmedImageCache: @unchecked Sendable {
    static let shared = TrimmedImageCache()

    private let queue = DispatchQueue(label: "wardrobe.trimmed-image-cache", attributes: .concurrent)
    private var storage: [String: UIImage] = [:]

    func get(_ key: String) -> UIImage? {
        queue.sync { storage[key] }
    }

    func set(_ image: UIImage, for key: String) {
        queue.async(flags: .barrier) {
            self.storage[key] = image
        }
    }
}
