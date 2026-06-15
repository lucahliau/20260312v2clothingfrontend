import SwiftUI

// MARK: - Collage

private struct BrandImageCollage: View {
    let items: [Item]
    @Binding var allImagesLoaded: Bool

    @State private var cellSettled: [Bool] = [false, false, false, false]

    var body: some View {
        GeometryReader { geo in
            let cell = (geo.size.width - 2) / 2
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    collageCell(item(at: 0), size: cell, index: 0)
                    collageCell(item(at: 1), size: cell, index: 1)
                }
                HStack(spacing: 2) {
                    collageCell(item(at: 2), size: cell, index: 2)
                    collageCell(item(at: 3), size: cell, index: 3)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            syncCellsFromItems()
        }
        .onChange(of: items.map(\.id)) { _, _ in
            syncCellsFromItems()
        }
    }

    private func syncCellsFromItems() {
        var next = [false, false, false, false]
        for i in 0..<4 {
            if let item = item(at: i), item.firstOriginalImageURL != nil {
                next[i] = false
            } else {
                next[i] = true
            }
        }
        cellSettled = next
        updateAllLoaded()
    }

    private func updateAllLoaded() {
        allImagesLoaded = cellSettled.allSatisfy { $0 }
    }

    private func bindingForCell(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { cellSettled[index] },
            set: { newValue in
                guard newValue else { return }
                var next = cellSettled
                next[index] = true
                cellSettled = next
                updateAllLoaded()
            }
        )
    }

    private func item(at index: Int) -> Item? {
        guard index < items.count else { return nil }
        return items[index]
    }

    @ViewBuilder
    private func collageCell(_ item: Item?, size: CGFloat, index: Int) -> some View {
        Group {
            if let item, let url = item.firstOriginalImageURL {
                CachedAsyncImage(
                    url: url,
                    fallbackUrl: item.secondOriginalImageURL,
                    loadFinished: bindingForCell(index),
                    resetsLoadingBinding: false
                )
                .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.28))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: size * 0.22))
                            .foregroundStyle(Color.appSecondaryText)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

// MARK: - Featured row

private struct FeaturedBrandRow: View {
    let brand: BrandInfo
    let previewItems: [Item]

    @State private var collageReady = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                if !collageReady {
                    FeaturedBrandCollageSkeleton()
                }
                BrandImageCollage(items: previewItems, allImagesLoaded: $collageReady)
                    .opacity(collageReady ? 1 : 0)
            }

            if collageReady {
                Text(brand.brand.displayNormalizedTitle)
                    .font(.appDisplay(size: 20))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(2)
                Text("\(brand.productCount) products")
                    .font(.appDisplay(size: 14))
                    .foregroundStyle(Color.appSecondaryText)
            } else {
                GhostBlock(height: 20, cornerRadius: 5, widthFraction: 0.72)
                GhostBlock(height: 14, cornerRadius: 4, widthFraction: 0.38)
            }
        }
        .animation(.easeOut(duration: 0.2), value: collageReady)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .popArtCardContainer()
    }
}

// MARK: - Explore

struct ExploreView: View {
    @Environment(ExploreViewModel.self) private var exploreModel
    @State private var selectedProduct: Item?
    @FocusState private var searchFieldFocused: Bool

    private var trimmedQuery: String {
        exploreModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let gridColumns = [
        GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)
    ]

    var body: some View {
        @Bindable var exploreModel = exploreModel
        VStack(spacing: 0) {
            PopArtTitleBar("Explore")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    searchBarContent(binding: $exploreModel.searchText, isFocused: $searchFieldFocused)

                    if trimmedQuery.isEmpty {
                        featuredSection
                    } else {
                        searchResultsContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            async let saved: Void = exploreModel.refreshSavedBrands()
            await exploreModel.loadFeaturedIfNeeded()
            await saved
        }
        .onAppear {
            Task { await exploreModel.refreshSavedBrands() }
        }
        .onChange(of: exploreModel.searchText) { _, _ in
            exploreModel.onSearchTextChanged()
        }
        .sheet(item: $selectedProduct) { item in
            NavigationStack {
                ItemDetailView(item: item, isPresented: true)
            }
        }
        .overlay {
            if let message = exploreModel.errorMessage {
                PopArtMessageAlert(title: "Error", message: message) {
                    exploreModel.errorMessage = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.22), value: exploreModel.errorMessage)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    searchFieldFocused = false
                }
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appAccent)
            }
        }
    }

    private func searchBarContent(binding: Binding<String>, isFocused: FocusState<Bool>.Binding) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondaryText)
            TextField(
                "",
                text: binding,
                prompt: Text("Search products or brands").foregroundStyle(Color(white: 0.42))
            )
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appPrimaryText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(isFocused)
                .submitLabel(.search)
                .accessibilityLabel("Search products or brands")
                .onSubmit {
                    searchFieldFocused = false
                }
            if searchFieldFocused {
                Button("Done") {
                    searchFieldFocused = false
                }
                .font(.appDisplay(size: 15))
                .foregroundStyle(Color.appAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .popArtCardContainer()
    }

    @ViewBuilder
    private var savedBrandsSection: some View {
        if !exploreModel.savedBrands.isEmpty {
            Text("Saved brands")
                .font(.appDisplay(size: 13))
                .tracking(0.8)
                .foregroundStyle(Color.appOnHalftoneSecondary)
                .textCase(.uppercase)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(exploreModel.savedBrands) { info in
                        NavigationLink {
                            BrandProductsView(brandName: info.brand)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.appNeonPink)
                                Text(info.brand.displayNormalizedTitle)
                                    .font(.appDisplay(size: 14))
                                    .foregroundStyle(Color.appPrimaryText)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white))
                            .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                            .background(Capsule().fill(Color.black).offset(x: 2, y: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 2)
            }
        }
    }

    @ViewBuilder
    private var featuredSection: some View {
        savedBrandsSection
        if exploreModel.isLoadingFeatured {
            FeaturedBrandsSectionSkeletonView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading featured brands")
        } else if exploreModel.featuredBrands.isEmpty {
            ContentUnavailableView {
                Label("No featured brands", systemImage: "sparkles")
                    .font(.appDisplay(size: 20))
                    .foregroundStyle(Color.appOnHalftonePrimary)
            } description: {
                Text("Check back later.")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
            }
        } else {
            Text("Featured brands")
                .font(.appDisplay(size: 13))
                .tracking(0.8)
                .foregroundStyle(Color.appOnHalftoneSecondary)
                .textCase(.uppercase)

            VStack(spacing: 16) {
                ForEach(exploreModel.featuredBrands) { info in
                    NavigationLink {
                        BrandProductsView(brandName: info.brand)
                    } label: {
                        FeaturedBrandRow(
                            brand: info,
                            previewItems: exploreModel.featuredPreviewItems[info.brand] ?? []
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if exploreModel.isSearching {
            ExploreSearchLoadingSkeletonView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityLabel("Searching")
        } else {
            if !exploreModel.brandResults.isEmpty {
                Text("Brands")
                    .font(.appDisplay(size: 13))
                    .tracking(0.8)
                    .foregroundStyle(Color.appOnHalftoneSecondary)
                    .textCase(.uppercase)

                VStack(spacing: 10) {
                    ForEach(exploreModel.brandResults) { brand in
                        NavigationLink {
                            BrandProductsView(brandName: brand.brand)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(brand.brand.displayNormalizedTitle)
                                        .font(.appDisplay(size: 17))
                                        .foregroundStyle(Color.appPrimaryText)
                                    Text("\(brand.productCount) products")
                                        .font(.appDisplay(size: 14))
                                        .foregroundStyle(Color.appSecondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.appSecondaryText)
                            }
                            .padding(14)
                            .popArtCardContainer()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !exploreModel.productResults.isEmpty {
                Text("Products")
                    .font(.appDisplay(size: 13))
                    .tracking(0.8)
                    .foregroundStyle(Color.appOnHalftoneSecondary)
                    .textCase(.uppercase)
                    .padding(.top, exploreModel.brandResults.isEmpty ? 0 : 8)

                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(Array(exploreModel.productResults.enumerated()), id: \.element.id) { index, item in
                        Button {
                            selectedProduct = item
                        } label: {
                            ExploreProductCell(
                                item: item,
                                onUnrecoverableHTTP404: { [id = item.id] in
                                    if selectedProduct?.id != id {
                                        exploreModel.removeProductResult(id: id)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            Task { await exploreModel.loadMoreProductResultsIfNeeded(currentIndex: index) }
                        }
                    }
                }

                if exploreModel.isLoadingMoreProducts {
                    ExploreProductGridSkeletonView(cellCount: 4)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Loading more products")
                }
            }

            if !exploreModel.isSearching, exploreModel.brandResults.isEmpty, exploreModel.productResults.isEmpty {
                ContentUnavailableView {
                    Label("No results", systemImage: "magnifyingglass")
                        .font(.appDisplay(size: 20))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                } description: {
                    Text("Try a different search.")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appOnHalftoneSecondary)
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - Product thumbnail (search grid)

private struct ExploreProductCell: View {
    let item: Item
    /// Full product photos (not background-removed) for brand grid; feed-style nobg for search.
    var useOriginalProductImages: Bool = false
    /// Card chrome: white panel with the name/price INSIDE (black on white),
    /// thick outline + offset extrusion. Used by the brand grid so text never
    /// floats transparently over the halftone; the Explore search grid keeps
    /// the lighter floating style.
    var carded: Bool = false
    /// Optional drop hook: invoked when both primary and fallback URLs return 404. Brand page wires this
    /// to `BrandProductsViewModel.removeItem(id:)`; Explore landing leaves it nil.
    var onUnrecoverableHTTP404: (() -> Void)? = nil

    @State private var imageReady = false

    private var needsImageFetch: Bool {
        if useOriginalProductImages, item.firstOriginalImageURL != nil { return true }
        if let pair = item.imageUrlPairs.first, URL(string: pair.primary) != nil { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ExploreProductCellSkeleton()
                .opacity(imageReady ? 0 : 1)
            Group {
                if carded {
                    cardedBody
                } else {
                    floatingBody
                }
            }
            .opacity(imageReady ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: imageReady)
        .onAppear {
            if !needsImageFetch {
                imageReady = true
            }
        }
        .onChange(of: item.id) { _, _ in
            imageReady = !needsImageFetch
        }
    }

    /// Strict square: the white base OWNS the layout (1:1 of the column
    /// width); the image is only painted in an overlay and clipped, so an
    /// oversized `scaledToFill` photo can never stretch the cell and break
    /// the grid alignment.
    private var productImage: some View {
        Color.white
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .overlay { imageLayer }
            .clipped()
    }

    @ViewBuilder
    private var imageLayer: some View {
        if useOriginalProductImages, let url = item.firstOriginalImageURL {
            CachedAsyncImage(
                url: url,
                fallbackUrl: item.secondOriginalImageURL,
                loadFinished: $imageReady,
                onUnrecoverableHTTP404: onUnrecoverableHTTP404
            )
            .scaledToFill()
        } else if let pair = item.imageUrlPairs.first, let url = URL(string: pair.primary) {
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                loadFinished: $imageReady,
                onUnrecoverableHTTP404: onUnrecoverableHTTP404
            )
            .scaledToFill()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.appSecondaryText)
                }
        }
    }

    private var floatingBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            productImage
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.black, lineWidth: 2)
                )

            Text(item.name.displayNormalizedTitle)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appOnHalftonePrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let price = item.priceDouble {
                Text(priceText(price))
                    .font(.appDisplay(size: 12))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
            }
        }
    }

    /// White pop-art card with name + price inside (matches the app's card
    /// language); fixed-height text block keeps grid rows aligned.
    private var cardedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            productImage
            Rectangle()
                .fill(Color.black)
                .frame(height: 2)
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
            .padding(10)
            .frame(height: 64, alignment: .top)
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

    private func priceText(_ price: Double) -> String {
        item.currency.map { "\(formatPrice(price)) \($0)" } ?? formatPrice(price)
    }

    private func formatPrice(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Brand products

private enum BrandFilterOverlay: Identifiable {
    case category
    case gender
    case price
    case sort

    var id: String {
        switch self {
        case .category: return "category"
        case .gender: return "gender"
        case .price: return "price"
        case .sort: return "sort"
        }
    }

    var sheetTitle: String {
        switch self {
        case .category: return "Type"
        case .gender: return "Gender"
        case .price: return "Price"
        case .sort: return "Sort"
        }
    }
}

struct BrandProductsView: View {
    @State private var viewModel: BrandProductsViewModel
    @State private var selectedItem: Item?
    @State private var shareItem: Item?
    @State private var filterOverlay: BrandFilterOverlay?

    private var theme: BrandBannerTheme {
        BrandBannerTheme.theme(for: viewModel.brandName)
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init(brandName: String) {
        _viewModel = State(initialValue: BrandProductsViewModel(brandName: brandName))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                BrandHeroHeader(
                    brandName: viewModel.brandName,
                    itemCount: viewModel.items.count,
                    hasMore: viewModel.hasMore,
                    theme: theme,
                    isSaved: viewModel.isSavedBrand,
                    onToggleSave: {
                        Task { await viewModel.toggleSavedBrand() }
                    }
                )

                Section {
                    if viewModel.isLoading && viewModel.items.isEmpty {
                        ExploreProductGridSkeletonView(cellCount: 8)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Loading products")
                    } else if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    selectedItem = item
                                }                                 label: {
                                    ExploreProductCell(
                                        item: item,
                                        useOriginalProductImages: true,
                                        carded: true,
                                        onUnrecoverableHTTP404: { [id = item.id] in
                                            if selectedItem?.id != id {
                                                viewModel.removeItem(id: id)
                                            }
                                        }
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button {
                                        Task { try? await SwipeService.recordSwipe(itemId: item.id, type: .LOVE) }
                                    } label: {
                                        Label("Love", systemImage: "heart.fill")
                                    }
                                    Button {
                                        Task { try? await SwipeService.recordSwipe(itemId: item.id, type: .LIKE) }
                                    } label: {
                                        Label("Like", systemImage: "hand.thumbsup.fill")
                                    }
                                    Button {
                                        shareItem = item
                                    } label: {
                                        Label("Send to a friend", systemImage: "paperplane.fill")
                                    }
                                }
                                .onAppear {
                                    viewModel.prefetchUpcoming(currentIndex: index)
                                    Task { await viewModel.loadMoreIfNeeded(currentIndex: index) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                        if viewModel.isLoadingMore {
                            ExploreProductGridSkeletonView(cellCount: 4)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                                .allowsHitTesting(false)
                                .accessibilityLabel("Loading more products")
                        }
                    }
                } header: {
                    // One pinned surface holds the filter chips AND the active
                    // filter pills, so nothing scrolls away independently.
                    VStack(spacing: 0) {
                        BrandStickyBar(
                            categorySelection: viewModel.selectedCategory,
                            genderSelection: viewModel.selectedGender,
                            priceSelection: viewModel.selectedPriceRange,
                            sortOption: viewModel.sortOption,
                            showCategoryChip: !viewModel.facetCategories.isEmpty,
                            showGenderChip: !viewModel.facetGenders.isEmpty,
                            onTapCategory: { filterOverlay = .category },
                            onTapGender: { filterOverlay = .gender },
                            onTapPrice: { filterOverlay = .price },
                            onTapSort: { filterOverlay = .sort }
                        )
                        BrandActiveFilterChips(
                            categorySelection: viewModel.selectedCategory,
                            genderSelection: viewModel.selectedGender,
                            priceSelection: viewModel.selectedPriceRange,
                            sortOption: viewModel.sortOption,
                            onClearCategory: { viewModel.setCategoryFilter(nil) },
                            onClearGender: { viewModel.setGenderFilter(nil) },
                            onClearPrice: { viewModel.setPriceFilter(nil) },
                            onClearSort: { viewModel.setSortOption(.featured) }
                        )
                    }
                    .background(theme.background)
                    .overlay(
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 2.5)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle(viewModel.brandName.displayNormalizedTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Solid bar so the back button and title never float over content.
        .toolbarBackground(theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            async let saved: Void = viewModel.loadSavedBrandState()
            await viewModel.loadInitial()
            await ImageCacheService.shared.warmMemoryFromDisk(
                urls: viewModel.items.compactMap(\.firstOriginalImageURL),
                maxUrls: 60
            )
            await saved
        }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ItemDetailView(item: item, isPresented: true)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareItemSheet(item: item)
        }
        .sheet(item: $filterOverlay) { overlay in
            brandFilterSheet(overlay)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.paginationErrorMessage {
                paginationErrorToast(message: message)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if let message = viewModel.errorMessage {
                PopArtMessageAlert(title: "Error", message: message) {
                    viewModel.errorMessage = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.errorMessage)
        .animation(.easeOut(duration: 0.22), value: viewModel.paginationErrorMessage)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label("No products", systemImage: "tshirt")
                    .font(.appDisplay(size: 20))
                    .foregroundStyle(Color.appPrimaryText)
            } description: {
                Text("No items match these filters.")
                    .font(.appDisplay(size: 16))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .popArtCardContainer()
        .padding(.horizontal, 20)
        .padding(.trailing, PopArtCardStyle.shadowOffset)
        .padding(.top, 20)
    }

    private func paginationErrorToast(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load more")
                    .font(.appDisplay(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                Text(message)
                    .font(.appDisplay(size: 12))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                Task { await viewModel.retryPagination() }
            } label: {
                Text("Retry")
                    .font(.appDisplay(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appPrimaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appPrimaryText)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black, lineWidth: 2)
        )
    }

    @ViewBuilder
    private func brandFilterSheet(_ overlay: BrandFilterOverlay) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    switch overlay {
                    case .category:
                        PopArtSelectionRow(
                            label: "All",
                            isSelected: viewModel.selectedCategory == nil
                        ) {
                            viewModel.setCategoryFilter(nil)
                            filterOverlay = nil
                        }
                        ForEach(viewModel.facetCategories, id: \.self) { cat in
                            PopArtSelectionRow(
                                label: cat.displayNormalizedTitle,
                                isSelected: viewModel.selectedCategory == cat
                            ) {
                                viewModel.setCategoryFilter(cat)
                                filterOverlay = nil
                            }
                        }
                    case .gender:
                        PopArtSelectionRow(
                            label: "All",
                            isSelected: viewModel.selectedGender == nil
                        ) {
                            viewModel.setGenderFilter(nil)
                            filterOverlay = nil
                        }
                        ForEach(viewModel.facetGenders, id: \.self) { g in
                            PopArtSelectionRow(
                                label: g.displayNormalizedTitle,
                                isSelected: viewModel.selectedGender == g
                            ) {
                                viewModel.setGenderFilter(g)
                                filterOverlay = nil
                            }
                        }
                    case .price:
                        PopArtSelectionRow(
                            label: "All",
                            isSelected: viewModel.selectedPriceRange == nil
                        ) {
                            viewModel.setPriceFilter(nil)
                            filterOverlay = nil
                        }
                        ForEach(BrandPriceRange.allCases) { range in
                            PopArtSelectionRow(
                                label: range.displayLabel,
                                isSelected: viewModel.selectedPriceRange == range
                            ) {
                                viewModel.setPriceFilter(range)
                                filterOverlay = nil
                            }
                        }
                    case .sort:
                        ForEach(BrandSortOption.allCases) { option in
                            PopArtSelectionRow(
                                label: option.displayLabel,
                                isSelected: viewModel.sortOption == option
                            ) {
                                viewModel.setSortOption(option)
                                filterOverlay = nil
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .navigationTitle(overlay.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        filterOverlay = nil
                    }
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appAccent)
                }
            }
        }
    }
}
