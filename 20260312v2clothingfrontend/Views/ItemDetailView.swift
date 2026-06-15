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
    @State private var shareSheetPresented = false
    @State private var swipeSaveError: String?
    @State private var similarItems: [Item] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                if hasValidSourceURL {
                    websiteCTA
                }
                shareCTA
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
                interactionCard
                if !similarItems.isEmpty {
                    moreLikeThisSection
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
        .task(id: item.id) {
            await loadSimilar()
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
        .sheet(isPresented: $shareSheetPresented) {
            ShareItemSheet(item: item)
        }
        .overlay {
            if let message = swipeSaveError {
                PopArtMessageAlert(title: "Error", message: message) {
                    swipeSaveError = nil
                }
                .zIndex(100)
            }
        }
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
            Text(item.name.displayNormalizedTitle)
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

    private var shareCTA: some View {
        PopArtPrimaryActionButton(title: "Send to a friend", systemImage: "paperplane.fill") {
            shareSheetPresented = true
        }
    }

    /// Love/Like/Neutral/Dislike. With an existing swipe record (wardrobe,
    /// history) the host's update callback runs; without one (brand page,
    /// explore) the pick records a fresh swipe directly.
    private var interactionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeaderInCard(swipeRecord == nil ? "Save it" : "Your interaction")
            VStack(spacing: 10) {
                ForEach(Self.interactionChoices, id: \.self) { action in
                    PopArtSelectionRow(
                        label: Self.swipeDisplayName(action),
                        isSelected: (selectedAction ?? swipeRecord?.action) == action
                    ) {
                        guard !isUpdatingSwipe else { return }
                        let previous = selectedAction
                        selectedAction = action
                        Task {
                            isUpdatingSwipe = true
                            if swipeRecord != nil, let onUpdate = onSwipeUpdated {
                                await onUpdate(action)
                            } else {
                                do {
                                    try await SwipeService.recordSwipe(itemId: item.id, type: action)
                                } catch {
                                    selectedAction = previous
                                    swipeSaveError = error.localizedDescription
                                }
                            }
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
                detailLabeledRow(label: "Brand", value: brand.displayNormalizedTitle)
            }
            if let category = item.category, !category.isEmpty {
                detailLabeledRow(label: "Category", value: category.displayNormalizedTitle)
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
                        Text(value.displayNormalizedTitle)
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

    // MARK: - More like this

    /// Horizontal rail of visually similar items (CLIP image-embedding ANN on
    /// the backend). Tapping one pushes its detail within the same nav stack.
    private var moreLikeThisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeaderOnHalftone("More like this")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(similarItems) { sim in
                        NavigationLink {
                            ItemDetailView(item: sim, isPresented: false)
                        } label: {
                            SimilarItemTile(item: sim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Loads the similar-items rail. Non-fatal: on failure the rail just stays hidden.
    private func loadSimilar() async {
        guard similarItems.isEmpty else { return }
        do {
            let items = try await ItemService.fetchSimilarItems(id: item.id, limit: 12)
            similarItems = items.filter { $0.id != item.id }
        } catch {
            // Silent: the rail simply doesn't appear.
        }
    }
}

// MARK: - Similar item tile

/// Compact carded product tile for the "More like this" rail — mirrors the
/// brand grid's card language (white panel, black outline + offset extrusion,
/// neon price).
private struct SimilarItemTile: View {
    let item: Item

    @State private var loaded = false

    private var imageURL: URL? {
        if let u = item.firstOriginalImageURL { return u }
        if let pair = item.imageUrlPairs.first { return URL(string: pair.primary) }
        return nil
    }

    private var fallbackURL: URL? {
        if let u = item.secondOriginalImageURL { return u }
        if let pair = item.imageUrlPairs.first, let fb = pair.fallback { return URL(string: fb) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.white
                if let url = imageURL {
                    CachedAsyncImage(url: url, fallbackUrl: fallbackURL, loadFinished: $loaded)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .frame(width: 130, height: 130)
            .clipped()

            Rectangle().fill(Color.black).frame(height: 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name.displayNormalizedTitle)
                    .font(.appDisplay(size: 12.5))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                Spacer(minLength: 0)
                if let price = item.priceDouble {
                    Text(priceText(price))
                        .font(.appDisplay(size: 12))
                        .foregroundStyle(Color.appNeonPink)
                }
            }
            .padding(8)
            .frame(width: 130, height: 56, alignment: .topLeading)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black, lineWidth: 2.5)
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .offset(x: 4, y: 4)
        )
    }

    private func priceText(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        let s = f.string(from: NSNumber(value: value)) ?? "\(value)"
        return item.currency.map { "\(s) \($0)" } ?? s
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
        // Solid white behind the photo: if the background-removed fallback
        // loads, its transparency reads on white instead of the dark page.
        .background(Color.white)
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
