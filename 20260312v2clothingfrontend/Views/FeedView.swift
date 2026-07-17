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
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @State private var selectedItem: Item?
    @State private var filterOverlay: FeedFilterOverlay?
    @State private var matchDetail: FeedMatch?
    /// When the user taps a contributor inside the explainer, we close the
    /// explainer first then push the item detail to keep SwiftUI sheet
    /// presentation single-stack.
    @State private var pendingContributorItemId: String?

    private var connectivity: ConnectivityMonitor { .shared }

    private var hasActiveFilters: Bool {
        !viewModel.selectedProductTypes.isEmpty || !viewModel.selectedGenders.isEmpty
    }

    /// Subway mode: cached cards keep working and swipes queue locally; this
    /// strip just tells the user what's happening instead of erroring.
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .bold))
            Text("You're offline — swipes will sync when you're back")
                .font(.appDisplay(size: 12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.appPrimaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color(red: 1.0, green: 0.85, blue: 0.2))
        .overlay(
            Rectangle()
                .fill(Color.black)
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Empty/caught-up state with a way out: refresh, and clear filters when
    /// they're what's starving the feed.
    private func feedEmptyState(title: String, icon: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .font(.appDisplay(size: 22))
                .foregroundStyle(Color.appOnHalftonePrimary)
        } description: {
            Text(message)
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appOnHalftoneSecondary)
        } actions: {
            VStack(spacing: 10) {
                Button {
                    Task { await viewModel.loadItems() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.appDisplay(size: 14))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.appNeonPink))
                        .overlay(Capsule().stroke(Color.black, lineWidth: 2.5))
                        .background(Capsule().fill(Color.black).offset(x: 2.5, y: 2.5))
                }
                .buttonStyle(.plain)
                if hasActiveFilters {
                    Button {
                        viewModel.selectedProductTypes = []
                        viewModel.selectedGenders = []
                        Task { await viewModel.loadItems() }
                    } label: {
                        Text("Clear filters")
                            .font(.appDisplay(size: 13))
                            .foregroundStyle(Color.appPrimaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.white))
                            .overlay(Capsule().stroke(Color.black, lineWidth: 2.5))
                            .background(Capsule().fill(Color.black).offset(x: 2.5, y: 2.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PopArtTitleBar("Feed")
            filterBar
            if !connectivity.isOnline {
                offlineBanner
            }
            Group {
                if viewModel.isLoading {
                    FeedCardStackSkeletonView()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                        .padding(.trailing, popArtCardShadowPadding)
                        .padding(.bottom, popArtCardShadowPadding)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Loading feed")
                } else if !viewModel.hasMoreItems && viewModel.items.isEmpty {
                    feedEmptyState(
                        title: "No items",
                        icon: "tray",
                        message: hasActiveFilters
                            ? "Nothing matches your filters right now."
                            : "Check back later for new items."
                    )
                } else if !viewModel.hasMoreItems && viewModel.isLoadingMore {
                    FeedCardStackSkeletonView()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                        .padding(.trailing, popArtCardShadowPadding)
                        .padding(.bottom, popArtCardShadowPadding)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Loading more feed items")
                } else if !viewModel.hasMoreItems, viewModel.loadMoreErrorMessage != nil {
                    feedEmptyState(
                        title: "Couldn't load more",
                        icon: "wifi.exclamationmark",
                        message: "Your feed still has more items. Check your connection and retry."
                    )
                } else if !viewModel.hasMoreItems && viewModel.isFeedExhausted {
                    feedEmptyState(
                        title: "All caught up",
                        icon: "checkmark.circle",
                        message: hasActiveFilters
                            ? "You've seen everything matching your filters."
                            : "You've seen all items. Check back later."
                    )
                } else if !viewModel.hasMoreItems {
                    FeedCardStackSkeletonView()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 40)
                        .padding(.trailing, popArtCardShadowPadding)
                        .padding(.bottom, popArtCardShadowPadding)
                        .allowsHitTesting(false)
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
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.loadIfNeeded() }
        /// When profile gender changes after the first successful profile fetch.
        .task(id: settingsViewModel.gender) {
            guard settingsViewModel.lastProfileLoadAt != nil else { return }
            let changed = viewModel.applyDefaultGenderFilterFromProfileIfNeeded(
                profileGender: settingsViewModel.gender.isEmpty ? nil : settingsViewModel.gender
            )
            if changed {
                await viewModel.loadItems()
            }
        }
        /// Run once when profile first loads (`nil` → date). Avatar uploads only bump the date, so this does not re-fire.
        .onChange(of: settingsViewModel.lastProfileLoadAt) { old, new in
            guard old == nil, new != nil else { return }
            Task {
                let changed = viewModel.applyDefaultGenderFilterFromProfileIfNeeded(
                    profileGender: settingsViewModel.gender.isEmpty ? nil : settingsViewModel.gender
                )
                if changed {
                    await viewModel.loadItems()
                }
            }
        }
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
        .sheet(item: $matchDetail, onDismiss: handleMatchSheetDismissed) { detail in
            MatchExplainerSheet(
                match: detail,
                onClose: { matchDetail = nil },
                onPickContributor: { contributor in
                    pendingContributorItemId = contributor.itemId
                    matchDetail = nil
                }
            )
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

    /// How many cards from the top of the deck stay mounted at once. The top
    /// card is interactive; the cards beneath it are pre-mounted so their image
    /// is already painted (and retained in view state, immune to cache
    /// eviction) before they're revealed. A swipe then PROMOTES the next card
    /// in place — it is never torn down and rebuilt — so there is no flash, no
    /// resize, and no re-fetch when the card above completes its swipe.
    private let visibleDeckDepth = 3

    /// The top `visibleDeckDepth` items paired with their depth (0 = top card).
    /// Drives the card window directly off `Item` (already `Identifiable`); the
    /// slice is clamped because `currentIndex` can momentarily reach
    /// `items.count` between a swipe and the next page append.
    private var visibleDeck: [(depth: Int, item: Item)] {
        guard !viewModel.items.isEmpty else { return [] }
        let lo = min(viewModel.currentIndex, viewModel.items.count)
        let hi = min(lo + visibleDeckDepth, viewModel.items.count)
        guard lo < hi else { return [] }
        return Array(viewModel.items[lo..<hi]).enumerated().map { (depth: $0.offset, item: $0.element) }
    }

    private var cardStack: some View {
        VStack(spacing: 10) {
            ZStack {
                ForEach(visibleDeck, id: \.item.id) { entry in
                    deckCard(item: entry.item, depth: entry.depth)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 40)
            .padding(.trailing, popArtCardShadowPadding)
            .padding(.bottom, popArtCardShadowPadding)

            if viewModel.showFeedSwipeHint {
                Text("Swipe the card to like or dislike. Tap it for more product details")
                    .font(.appDisplay(size: 12))
                    .fontWeight(.regular)
                    .foregroundStyle(Color.appOnHalftoneSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.showFeedSwipeHint)
    }

    /// One card in the windowed deck. The top card (depth 0) is interactive and
    /// the next card (depth 1) sits at the **same** transform behind it, so
    /// revealing it on swipe is a pure occlusion change — zero resize, zero
    /// flash. Only the deeper decorative peek (depth ≥ 2) is scaled/offset, and
    /// its promotion to depth 1 happens hidden behind the top card.
    @ViewBuilder
    private func deckCard(item: Item, depth: Int) -> some View {
        let isTop = depth == 0
        SwipeCardView(
            item: item,
            onSwipe: { action in
                await viewModel.recordSwipe(item: item, action: action)
            },
            onTap: {
                AnalyticsManager.shared.track("item_view", metadata: ["itemId": item.id])
                selectedItem = item
            },
            onUnrecoverableImage404: {
                viewModel.removeCurrentFeedItemIfBroken404(matchingItemId: item.id)
            },
            match: viewModel.match(for: item.id),
            onMatchTap: isTop ? viewModel.match(for: item.id).map { m in { matchDetail = m } } : nil
        )
        .scaleEffect(deckCardScale(depth: depth))
        .offset(y: deckCardOffsetY(depth: depth))
        .allowsHitTesting(isTop)
        // Explicit z-order by depth (top highest) so draw order never depends on
        // ForEach source order or churns on promotion.
        .zIndex(Double(visibleDeckDepth - depth))
        // The swiped card has already flown off via its own drag offset; suppress
        // the default opacity removal so it never re-fades into view.
        .transition(.identity)
    }

    /// Depth 0 and 1 share the top transform (no resize on reveal); the deeper
    /// peek matches the proven skeleton/placeholder values.
    private func deckCardScale(depth: Int) -> CGFloat {
        depth >= 2 ? 0.98 : 1.0
    }

    private func deckCardOffsetY(depth: Int) -> CGFloat {
        depth >= 2 ? 6 : 0
    }

    /// Room for SwipeCardView offset black “extrusion” without clipping.
    private var popArtCardShadowPadding: CGFloat { PopArtCardStyle.shadowOffset }

    /// Two-step transition: the explainer sheet must finish dismissing before
    /// we can present the contributor's item detail (SwiftUI only allows one
    /// modal at a time per anchor).
    private func handleMatchSheetDismissed() {
        guard let id = pendingContributorItemId else { return }
        pendingContributorItemId = nil
        Task { @MainActor in
            do {
                let item = try await ItemService.fetchItem(id: id)
                selectedItem = item
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Button {
                filterOverlay = .productType
            } label: {
                filterChipLabel(
                    title: "Type",
                    selection: viewModel.selectedProductTypes.isEmpty ? "All" : "Filtered",
                    isFiltered: !viewModel.selectedProductTypes.isEmpty,
                    accessibilitySummary: viewModel.selectedProductTypes.isEmpty
                        ? nil
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
                    selection: viewModel.selectedGenders.isEmpty ? "All" : "Filtered",
                    isFiltered: !viewModel.selectedGenders.isEmpty,
                    accessibilitySummary: viewModel.selectedGenders.isEmpty
                        ? nil
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
        .padding(.top, 4)
        .padding(.bottom, 10)
        .padding(.trailing, popArtCardShadowPadding)
        .padding(.bottom, 4)
    }

    private func filterChipLabel(title: String, selection: String, isFiltered: Bool, accessibilitySummary: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Text(selection)
                .font(.appDisplay(size: 14))
                .fontWeight(isFiltered ? .semibold : .regular)
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
        .accessibilityLabel(accessibilitySummary.map { "\(title): \($0)" } ?? "\(title): \(selection)")
    }
}
