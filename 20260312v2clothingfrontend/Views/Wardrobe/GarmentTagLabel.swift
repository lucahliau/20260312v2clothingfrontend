import SwiftUI

/// Swing-tag sticker for hanging garments: name + brand/price on a white
/// label with a black outline and hard offset shadow, slightly tilted like a
/// price tag looped over the hanger — replaces the old raw text floating
/// directly over the garment art.
struct GarmentTagLabel: View {
    let name: String
    var brand: String? = nil
    var price: Double? = nil
    var maxWidth: CGFloat = 132

    var body: some View {
        VStack(spacing: 1) {
            Text(name)
                .font(.appDisplay(size: 10.5))
                .foregroundStyle(Color.appPrimaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
            if hasSecondLine {
                HStack(spacing: 5) {
                    if let brand, !brand.isEmpty {
                        Text(brand)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    if let price {
                        Text("$\(Int(price.rounded()))")
                    }
                }
                .font(.appDisplay(size: 9))
                .foregroundStyle(Color.appSecondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.black, lineWidth: 2)
        )
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black)
                .offset(x: 2, y: 2)
        )
        .rotationEffect(.degrees(-2.5))
        .frame(maxWidth: maxWidth)
        .allowsHitTesting(false)
    }

    private var hasSecondLine: Bool {
        (brand?.isEmpty == false) || price != nil
    }
}
