import SwiftUI
import CoreText

extension Font {
    /// Montserrat Black (variable font `wght` = 900).
    static func appDisplay(size: CGFloat = 17) -> Font {
        let ui = UIFont.appDisplay(size: size)
        let ctFont = CTFont(ui.fontDescriptor as CTFontDescriptor, size: size)
        return Font(ctFont)
    }
}
