import SwiftUI
import UIKit

struct ItemDetailView: View {
    let item: Item
    var swipeRecord: SwipeRecord? = nil
    var onSwipeUpdated: ((SwipeType) async -> Void)? = nil
    var isPresented: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAction: SwipeType?
    @State private var isUpdatingSwipe = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                if hasValidSourceURL {
                    websiteCTA
                }
                if !item.imageUrls.isEmpty {
                    photosSection
                } else {
                    emptyPhotosPlaceholder
                }
                if hasDetailsContent {
                    detailsCard
                }
                if let description = item.description, !description.isEmpty {
                    aboutCard(description: description)
                }
                if swipeRecord != nil, onSwipeUpdated != nil {
                    interactionCard
                }
                if let createdAt = item.createdAt, !createdAt.isEmpty {
                    footerMeta(createdAt)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .padding(.bottom, 12)
        }
        .background {
            PopArtHalftoneBackground()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedAction = swipeRecord?.action
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Details")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appOnHalftonePrimary)
            }
            if isPresented {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                }
            }
        }
        .navigationTitle("")
    }

    private var hasValidSourceURL: Bool {
        guard let urlString = item.sourceUrl, !urlString.isEmpty else { return false }
        return URL(string: urlString) != nil
    }

    private var hasDetailsContent: Bool {
        if let b = item.brand, !b.isEmpty { return true }
        if let c = item.category, !c.isEmpty { return true }
        if item.priceDouble == nil, let p = item.price, !p.isEmpty { return true }
        if let c = item.colors, !c.isEmpty { return true }
        return false
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name)
                .font(.appDisplay(size: 28))
                .foregroundStyle(Color.appOnHalftonePrimary)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
                .fixedSize(horizontal: false, vertical: true)
            if let priceDouble = item.priceDouble {
                Text(formatPrice(priceDouble))
                    .font(.appDisplay(size: 22))
                    .foregroundStyle(Color.appAccent)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var websiteCTA: some View {
        PopArtPrimaryActionButton(title: "Shop on website", systemImage: "bag.fill") {
            guard let urlString = item.sourceUrl, let url = URL(string: urlString) else { return }
            UIApplication.shared.open(url)
        }
    }

    private static let interactionChoices: [SwipeType] = [.LOVE, .LIKE, .NEUTRAL, .DISLIKE]

    @ViewBuilder
    private var interactionCard: some View {
        if let record = swipeRecord, let onUpdate = onSwipeUpdated {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeaderInCard("Your interaction")
                VStack(spacing: 10) {
                    ForEach(Self.interactionChoices, id: \.self) { action in
                        PopArtSelectionRow(
                            label: Self.swipeDisplayName(action),
                            isSelected: (selectedAction ?? record.action) == action
                        ) {
                            guard !isUpdatingSwipe else { return }
                            selectedAction = action
                            Task {
                                isUpdatingSwipe = true
                                await onUpdate(action)
                                isUpdatingSwipe = false
                            }
                        }
                    }
                }
                .opacity(isUpdatingSwipe ? 0.55 : 1)
                if isUpdatingSwipe {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Updating…")
                            .font(.appDisplay(size: 15))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popArtCardContainer()
        }
    }

    private static func swipeDisplayName(_ type: SwipeType) -> String {
        switch type {
        case .LOVE: return "Love"
        case .LIKE: return "Like"
        case .NEUTRAL: return "Neutral"
        case .DISLIKE: return "Dislike"
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeaderOnHalftone("Photos")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(item.imageUrls, id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            let nobg = Item.useBackgroundRemovedImages
                                ? URL(string: urlString.imageUrlNoBg)
                                : nil
                            ItemDetailPhotoTile(url: url, fallbackUrl: nobg)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyPhotosPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeaderOnHalftone("Photos")
            RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius)
                .fill(Color.white.opacity(0.5))
                .frame(height: 200)
                .overlay {
                    Text("No images")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .popArtCardContainer()
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeaderInCard("Details")
            if let brand = item.brand, !brand.isEmpty {
                detailLabeledRow(label: "Brand", value: brand)
            }
            if let category = item.category, !category.isEmpty {
                detailLabeledRow(label: "Category", value: category)
            }
            if item.priceDouble == nil, let price = item.price, !price.isEmpty {
                detailLabeledRow(label: "Price", value: price)
            }
            if let colors = item.colors, !colors.isEmpty {
                chipRow(title: "Colors", values: colors)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private func aboutCard(description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeaderInCard("About")
            Text(description)
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private func footerMeta(_ createdAt: String) -> some View {
        Text("Added \(createdAt)")
            .font(.appDisplay(size: 14))
            .foregroundStyle(Color.appOnHalftoneSecondary)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    private func sectionHeaderOnHalftone(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.appDisplay(size: 12))
            .tracking(1.1)
            .foregroundStyle(Color.appOnHalftoneSecondary)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    private func sectionHeaderInCard(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.appDisplay(size: 12))
            .tracking(1.1)
            .foregroundStyle(Color.appSecondaryText)
    }

    private func detailLabeledRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.appDisplay(size: 14))
                .foregroundStyle(Color.appSecondaryText)
            Text(value)
                .font(.appDisplay(size: 18))
                .foregroundStyle(Color.appPrimaryText)
        }
    }

    private func chipRow(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appDisplay(size: 14))
                .foregroundStyle(Color.appSecondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.appDisplay(size: 15))
                            .foregroundStyle(Color.appPrimaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.appAccent.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.black.opacity(0.2), lineWidth: 2)
                            )
                    }
                }
            }
        }
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - Detail photo (ghost until loaded)

private struct ItemDetailPhotoTile: View {
    let url: URL
    let fallbackUrl: URL?

    @State private var loadFinished = false

    var body: some View {
        ZStack {
            GhostBlock(height: 300, cornerRadius: PopArtCardStyle.cornerRadius - 2)
                .frame(width: 300, height: 300)
                .opacity(loadFinished ? 0 : 1)
            CachedAsyncImage(url: url, fallbackUrl: fallbackUrl, loadFinished: $loadFinished)
                .aspectRatio(contentMode: .fill)
                .frame(width: 300, height: 300)
                .clipped()
                .opacity(loadFinished ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: loadFinished)
        .clipShape(RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius - 2))
        .overlay(
            RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius - 2)
                .stroke(Color.black, lineWidth: PopArtCardStyle.strokeWidth)
        )
        .background(
            RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius - 2)
                .fill(Color.black)
                .offset(x: PopArtCardStyle.shadowOffset, y: PopArtCardStyle.shadowOffset)
        )
    }
}
