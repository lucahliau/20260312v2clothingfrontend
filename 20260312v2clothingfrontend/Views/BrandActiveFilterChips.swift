import SwiftUI

/// Row of pop-art pills representing the brand page's active filters and sort.
/// Each pill has an `xmark` button that clears just that one filter. Hidden when nothing is active.
struct BrandActiveFilterChips: View {
    let categorySelection: String?
    let genderSelection: String?
    let priceSelection: BrandPriceRange?
    let sortOption: BrandSortOption
    let onClearCategory: () -> Void
    let onClearGender: () -> Void
    let onClearPrice: () -> Void
    let onClearSort: () -> Void

    private var hasAny: Bool {
        categorySelection != nil || genderSelection != nil || priceSelection != nil || sortOption != .featured
    }

    var body: some View {
        if hasAny {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let category = categorySelection {
                        ActiveFilterPill(
                            label: "Type: \(category.displayNormalizedTitle)",
                            action: onClearCategory
                        )
                    }
                    if let gender = genderSelection {
                        ActiveFilterPill(
                            label: "Gender: \(gender.displayNormalizedTitle)",
                            action: onClearGender
                        )
                    }
                    if let price = priceSelection {
                        ActiveFilterPill(
                            label: "Price: \(price.displayLabel)",
                            action: onClearPrice
                        )
                    }
                    if sortOption != .featured {
                        ActiveFilterPill(
                            label: "Sort: \(sortOption.displayLabel)",
                            action: onClearSort
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct ActiveFilterPill: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.appDisplay(size: 13))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.appNeonPink)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black, lineWidth: 2)
            )
            .background(
                Capsule()
                    .fill(Color.black)
                    .offset(x: 3, y: 3)
            )
            .accessibilityLabel("Clear \(label)")
        }
        .buttonStyle(.plain)
    }
}
