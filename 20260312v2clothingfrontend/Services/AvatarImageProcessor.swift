import UIKit

enum AvatarImageProcessor {
    private static let maxSide: CGFloat = 1024
    private static let jpegQuality: CGFloat = 0.85

    static func jpegDataForUpload(from image: UIImage) -> Data? {
        let scaled = image.scaledToMaxSide(maxSide)
        return scaled.jpegData(compressionQuality: jpegQuality)
    }
}

private extension UIImage {
    func scaledToMaxSide(_ maxSide: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        let longest = Swift.max(w, h)
        guard longest > maxSide, longest > 0 else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
