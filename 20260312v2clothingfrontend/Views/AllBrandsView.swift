import SwiftUI

/// A–Z list of every brand with its product count. Quick search field, a
/// letter strip that jumps to a section, and a toggle that hides tiny brands
/// (fewer than 10 products) by default. Rows open the regular brand page.
struct AllBrandsView: View {
    @State private var viewModel = AllBrandsViewModel()
    @AppStorage("allBrandsHideSmall") private var hideSmallBrands = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            ServerUnreachableBanner {
                await viewModel.load(hideSmall: hideSmallBrands)
            }
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    if viewModel.searchText.isEmpty, viewModel.sections.count > 1 {
                        letterStrip(proxy: proxy)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            searchField(text: $viewModel.searchText)
                            smallBrandsToggle
                            content
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                        .padding(.trailing, PopArtCardStyle.shadowOffset)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await viewModel.load(hideSmall: hideSmallBrands)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle("All brands")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appPopArtBlue, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .task(id: hideSmallBrands) {
            await viewModel.load(hideSmall: hideSmallBrands)
        }
    }

    // MARK: - Pieces

    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondaryText)
            TextField(
                "",
                text: text,
                prompt: Text("Find a brand").foregroundStyle(Color(white: 0.42))
            )
            .font(.appDisplay(size: 17))
            .foregroundStyle(Color.appPrimaryText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .submitLabel(.done)
            .accessibilityLabel("Find a brand")
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .popArtCardContainer()
    }

    private var smallBrandsToggle: some View {
        Toggle(isOn: $hideSmallBrands) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hide small brands")
                    .font(.appDisplay(size: 15))
                    .foregroundStyle(Color.appPrimaryText)
                Text("Fewer than \(AllBrandsViewModel.smallBrandThreshold) products")
                    .font(.appDisplay(size: 12))
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .tint(Color.appAccent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .popArtCardContainer()
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.brands.isEmpty, viewModel.isLoading || !viewModel.hasLoaded, viewModel.errorMessage == nil {
            VStack(spacing: 10) {
                ForEach(0..<8, id: \.self) { _ in
                    ExploreBrandSearchRowSkeleton()
                }
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Loading brands")
        } else if viewModel.brands.isEmpty, let message = viewModel.errorMessage {
            failureState(message: message)
        } else if viewModel.sections.isEmpty {
            ContentUnavailableView {
                Label("No brands", systemImage: "magnifyingglass")
                    .font(.appDisplay(size: 20))
                    .foregroundStyle(Color.appOnHalftonePrimary)
            } description: {
                Text(viewModel.searchText.isEmpty ? "Nothing to show yet." : "No brand matches “\(viewModel.searchText)”.")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
            }
        } else {
            Text("\(viewModel.filteredBrands.count) brands")
                .font(.appDisplay(size: 13))
                .tracking(0.8)
                .foregroundStyle(Color.appOnHalftoneSecondary)
                .textCase(.uppercase)

            ForEach(viewModel.sections) { section in
                Text(section.letter)
                    .font(.appDisplay(size: 20))
                    .foregroundStyle(Color.appOnHalftonePrimary)
                    .padding(.top, 4)
                    .id(section.letter)
                    .accessibilityAddTraits(.isHeader)

                ForEach(section.brands) { brand in
                    NavigationLink {
                        BrandProductsView(brandName: brand.brand)
                    } label: {
                        brandRow(brand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func brandRow(_ brand: BrandInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(brand.brand.displayNormalizedTitle)
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appPrimaryText)
                    .multilineTextAlignment(.leading)
                Text(brand.productCount == 1 ? "1 product" : "\(brand.productCount) products")
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

    private func failureState(message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load brands", systemImage: "wifi.exclamationmark")
                .font(.appDisplay(size: 20))
                .foregroundStyle(Color.appOnHalftonePrimary)
        } description: {
            Text(message)
                .font(.appDisplay(size: 15))
                .foregroundStyle(Color.appOnHalftoneSecondary)
        } actions: {
            ExploreRetryButton {
                await viewModel.load(hideSmall: hideSmallBrands)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Horizontal A–Z strip pinned above the list; tapping a letter scrolls to
    /// its section.
    private func letterStrip(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.sections) { section in
                    Button {
                        searchFocused = false
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(section.letter, anchor: .top)
                        }
                    } label: {
                        Text(section.letter)
                            .font(.appDisplay(size: 14))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appPrimaryText)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to \(section.letter)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.appPopArtBlue)
        .overlay(
            Rectangle()
                .fill(Color.black)
                .frame(height: 2.5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
    }
}

/// Pink pop-art capsule "Retry" used by Explore's inline failure states
/// (matches the Feed empty-state Refresh button).
struct ExploreRetryButton: View {
    var title: String = "Retry"
    let action: () async -> Void

    @State private var isRunning = false

    var body: some View {
        Button {
            guard !isRunning else { return }
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            Label(title, systemImage: "arrow.clockwise")
                .font(.appDisplay(size: 14))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.appNeonPink))
                .overlay(Capsule().stroke(Color.black, lineWidth: 2.5))
                .background(Capsule().fill(Color.black).offset(x: 2.5, y: 2.5))
                .opacity(isRunning ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }
}
