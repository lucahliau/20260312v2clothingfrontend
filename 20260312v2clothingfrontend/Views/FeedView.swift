import SwiftUI

private enum FeedFilterOverlay: Identifiable {
    case productType
    case gender

    var id: String {
        switch self {
        case .productType: return "productType"
        case .gender: return "gender"
        }
    }

    var sheetTitle: String {
        switch self {
        case .productType: return "Type"
        case .gender: return "Gender"
        }
    }
}

struct FeedView: View {
    @Environment(FeedViewModel.self) private var viewModel
    @State private var selectedItem: Item?
    @State private var filterOverlay: FeedFilterOverlay?

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Group {
                if viewModel.isLoading {
                    FeedCardStackSkeletonView()
                        .allowsHitTesting(false)
                        .accessibilityLabel("Loading feed")
                } else if !viewModel.hasMoreItems && viewModel.items.isEmpty {
                    ContentUnavailableView {
                        Label("No items", systemImage: "tray")
                            .font(.appDisplay(size: 22))
                            .foregroundStyle(Color.appOnHalftonePrimary)
                    } description: {
                        Text("Check back later for new items.")
                            .font(.appDisplay(size: 17))
                            .foregroundStyle(Color.appOnHalftoneSecondary)
                    }
                } else if !viewModel.hasMoreItems {
                    ContentUnavailableView {
                        Label("All caught up", systemImage: "checkmark.circle")
                            .font(.appDisplay(size: 22))
                            .foregroundStyle(Color.appOnHalftonePrimary)
                    } description: {
                        Text("You've seen all items. Check back later.")
                            .font(.appDisplay(size: 17))
                            .foregroundStyle(Color.appOnHalftoneSecondary)
                    }
                } else {
                    cardStack
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle("Feed")
        .task { await viewModel.loadIfNeeded() }
        .sheet(item: $selectedItem) { item in
            NavigationStack {
                ItemDetailView(item: item, isPresented: true)
            }
        }
        .sheet(item: $filterOverlay) { overlay in
            filterSheetContent(overlay)
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

    @ViewBuilder
    private func filterSheetContent(_ overlay: FeedFilterOverlay) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    switch overlay {
                    case .productType:
                        ForEach(ProductType.allCases, id: \.self) { type in
                            PopArtSelectionRow(
                                label: type.displayName,
                                isSelected: viewModel.selectedProductTypes.contains(type)
                            ) {
                                viewModel.toggleProductType(type)
                            }
                        }
                    case .gender:
                        ForEach(GenderFilter.allCases, id: \.self) { gender in
                            PopArtSelectionRow(
                                label: gender.displayName,
                                isSelected: viewModel.selectedGenders.contains(gender)
                            ) {
                                viewModel.toggleGender(gender)
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

    private var cardStack: some View {
        ZStack {
            if let nextItem = viewModel.currentIndex + 1 < viewModel.items.count
                ? viewModel.items[viewModel.currentIndex + 1] : nil
            {
                cardPlaceholder(item: nextItem)
            }
            if let item = viewModel.currentItem {
                SwipeCardView(
                    item: item,
                    onSwipe: { action in
                        await viewModel.recordSwipe(item: item, action: action)
                    },
                    onTap: { selectedItem = item }
                )
                .id(item.id)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .padding(.trailing, popArtCardShadowPadding)
        .padding(.bottom, popArtCardShadowPadding)
    }

    /// Room for SwipeCardView offset black “extrusion” without clipping.
    private var popArtCardShadowPadding: CGFloat { PopArtCardStyle.shadowOffset }

    private func cardPlaceholder(item: Item) -> some View {
        SwipeCardView(
            item: item,
            onSwipe: { _ in true },
            onTap: {}
        )
        .scaleEffect(0.98)
        .offset(y: 6)
        .allowsHitTesting(false)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Button {
                filterOverlay = .productType
            } label: {
                filterChipLabel(
                    title: "Type",
                    selection: viewModel.selectedProductTypes.isEmpty
                        ? "All"
                        : viewModel.selectedProductTypes.map(\.displayName).sorted().joined(separator: ", ")
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button {
                filterOverlay = .gender
            } label: {
                filterChipLabel(
                    title: "Gender",
                    selection: viewModel.selectedGenders.isEmpty
                        ? "All"
                        : viewModel.selectedGenders.map(\.displayName).sorted().joined(separator: ", ")
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .popArtCardContainer()
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .padding(.trailing, popArtCardShadowPadding)
        .padding(.bottom, 4)
    }

    private func filterChipLabel(title: String, selection: String) -> some View {
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
}
