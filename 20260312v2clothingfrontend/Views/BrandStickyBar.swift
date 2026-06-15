import SwiftUI

/// Filter chip row pinned above the brand grid: Type / Gender / Sort. Renders
/// transparent — the pinned-header container in `BrandProductsView` owns the
/// solid background and bottom rule so chips and active-filter pills share one
/// consistent surface.
struct BrandStickyBar: View {
    let categorySelection: String?
    let genderSelection: String?
    let priceSelection: BrandPriceRange?
    let sortOption: BrandSortOption
    let showCategoryChip: Bool
    let showGenderChip: Bool
    let onTapCategory: () -> Void
    let onTapGender: () -> Void
    let onTapPrice: () -> Void
    let onTapSort: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if showCategoryChip {
                    Button(action: onTapCategory) {
                        BrandStickyBarChipLabel(
                            title: "Type",
                            selection: categorySelection.map { $0.displayNormalizedTitle } ?? "All",
                            isFiltered: categorySelection != nil
                        )
                    }
                    .buttonStyle(.plain)
                }
                if showGenderChip {
                    Button(action: onTapGender) {
                        BrandStickyBarChipLabel(
                            title: "Gender",
                            selection: genderSelection.map { $0.displayNormalizedTitle } ?? "All",
                            isFiltered: genderSelection != nil
                        )
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onTapPrice) {
                    BrandStickyBarChipLabel(
                        title: "Price",
                        selection: priceSelection?.displayLabel ?? "All",
                        isFiltered: priceSelection != nil
                    )
                }
                .buttonStyle(.plain)
                Button(action: onTapSort) {
                    BrandStickyBarChipLabel(
                        title: "Sort",
                        selection: sortOption.displayLabel,
                        isFiltered: sortOption != .featured
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BrandStickyBarChipLabel: View {
    let title: String
    let selection: String
    let isFiltered: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Text(selection)
                .font(.appDisplay(size: 14))
                .fontWeight(isFiltered ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(Color.appPrimaryText)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)
        }
        .frame(minHeight: 36, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black, lineWidth: 2)
        )
        .accessibilityLabel("\(title): \(selection)")
    }
}
