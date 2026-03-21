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
                Text(brand.brand)
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
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await exploreModel.loadFeaturedIfNeeded()
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
                .foregroundStyle(Color.appOnHalftoneSecondary)
            TextField("Search products or brands", text: binding)
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appOnHalftonePrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(isFocused)
                .submitLabel(.search)
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
        .background(Color.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.black.opacity(0.35), lineWidth: 2)
        )
    }

    @ViewBuilder
    private var featuredSection: some View {
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
                                    Text(brand.brand)
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
                    ForEach(exploreModel.productResults) { item in
                        Button {
                            selectedProduct = item
                        } label: {
                            ExploreProductCell(item: item)
                        }
                        .buttonStyle(.plain)
                    }
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
            cellBody
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

    private var cellBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white
                if useOriginalProductImages, let url = item.firstOriginalImageURL {
                    CachedAsyncImage(
                        url: url,
                        fallbackUrl: item.secondOriginalImageURL,
                        loadFinished: $imageReady
                    )
                    .scaledToFill()
                } else if let pair = item.imageUrlPairs.first, let url = URL(string: pair.primary) {
                    CachedAsyncImage(
                        url: url,
                        fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                        loadFinished: $imageReady
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
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black, lineWidth: 2)
            )

            Text(item.name)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appOnHalftonePrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let price = item.priceDouble {
                Text(item.currency.map { "\(formatPrice(price)) \($0)" } ?? formatPrice(price))
                    .font(.appDisplay(size: 12))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
            }
        }
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

    var id: String {
        switch self {
        case .category: return "category"
        case .gender: return "gender"
        }
    }

    var sheetTitle: String {
        switch self {
        case .category: return "Type"
        case .gender: return "Gender"
        }
    }
}

struct BrandProductsView: View {
    @State private var viewModel: BrandProductsViewModel
    @State private var selectedItem: Item?
    @State private var filterOverlay: BrandFilterOverlay?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)
    ]

    private var popArtCardShadowPadding: CGFloat { PopArtCardStyle.shadowOffset }

    private var showBrandFilters: Bool {
        !viewModel.facetCategories.isEmpty || !viewModel.facetGenders.isEmpty
    }

    init(brandName: String) {
        _viewModel = State(initialValue: BrandProductsViewModel(brandName: brandName))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ScrollView {
                    ExploreProductGridSkeletonView(cellCount: 9)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading products")
            } else if viewModel.items.isEmpty {
                ScrollView {
                    VStack(spacing: 16) {
                        if showBrandFilters {
                            brandFilterBar
                        }
                        ContentUnavailableView {
                            Label("No products", systemImage: "tshirt")
                                .font(.appDisplay(size: 20))
                                .foregroundStyle(Color.appOnHalftonePrimary)
                        } description: {
                            Text("This brand has no items to show.")
                                .font(.appDisplay(size: 17))
                                .foregroundStyle(Color.appOnHalftoneSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, showBrandFilters ? 8 : 0)
                    }
                    .padding(.vertical, 16)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if showBrandFilters {
                            brandFilterBar
                        }
                        LazyVGrid(columns: gridColumns, spacing: 14) {
                            ForEach(viewModel.items) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    ExploreProductCell(item: item, useOriginalProductImages: true)
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    if item.id == viewModel.items.last?.id {
                                        Task { await viewModel.loadMoreIfNeeded() }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle(viewModel.brandName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadFacetsProbe()
            await viewModel.loadInitial()
        }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ItemDetailView(item: item, isPresented: true)
            }
        }
        .sheet(item: $filterOverlay) { overlay in
            brandFilterSheet(overlay)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
    }

    private var brandFilterBar: some View {
        HStack(spacing: 10) {
            if !viewModel.facetCategories.isEmpty {
                Button {
                    filterOverlay = .category
                } label: {
                    brandFilterChipLabel(
                        title: "Type",
                        selection: viewModel.selectedCategory ?? "All"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            if !viewModel.facetGenders.isEmpty {
                Button {
                    filterOverlay = .gender
                } label: {
                    brandFilterChipLabel(
                        title: "Gender",
                        selection: viewModel.selectedGender ?? "All"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .popArtCardContainer()
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.trailing, popArtCardShadowPadding)
        .padding(.bottom, 4)
    }

    private func brandFilterChipLabel(title: String, selection: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Text(selection)
                .font(.appDisplay(size: 14))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)
        }
        .foregroundStyle(Color.appPrimaryText)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
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
                                label: cat,
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
                                label: g,
                                isSelected: viewModel.selectedGender == g
                            ) {
                                viewModel.setGenderFilter(g)
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
