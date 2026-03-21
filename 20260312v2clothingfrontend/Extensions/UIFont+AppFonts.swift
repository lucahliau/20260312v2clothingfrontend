import UIKit
import CoreText

extension UIFont {
    /// Montserrat “Black” (weight 900) via variable font, or system black fallback.
    static func appDisplay(size: CGFloat) -> UIFont {
        let candidates = ["Montserrat-Regular", "Montserrat"]
        for name in candidates {
            if let base = UIFont(name: name, size: size) {
                return applyWghtAxis(base, size: size, weight: 900)
            }
        }
        return .systemFont(ofSize: size, weight: .black)
    }

    private static func applyWghtAxis(_ base: UIFont, size: CGFloat, weight: CGFloat) -> UIFont {
        let wghtTag = NSNumber(value: Int(0x77676874)) // 'wght'
        let variation: [NSNumber: CGFloat] = [wghtTag: weight]
        let attrs: [UIFontDescriptor.AttributeName: Any] = [
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): variation
        ]
        let desc = base.fontDescriptor.addingAttributes(attrs)
        return UIFont(descriptor: desc, size: size)
    }
}
