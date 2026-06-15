import SwiftUI

/// The Wardrobe tab — pop-art closet on the app's halftone wallpaper. Two
/// independently scrolling rails (tops & jackets up top, bottoms below) let
/// you mix and match outfits by flicking each rail; bags stand on a shelf,
/// shoes on a rack, and collections live in a pull-open drawer.
struct ClosetView: View {
    @Environment(SwipeHistoryViewModel.self) private var historyViewModel
    @Environment(WardrobeViewModel.self) private var viewModel
    @Environment(TabRouter.self) private var tabRouter

    @State private var selectedContext: HistoryDetailContext?
    @State private var searchActive = false
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var drawerOpen: Bool = {
        #if DEBUG
        // Screenshot hook: SIMCTL_CHILD_DEMO_DRAWER=1 starts with the drawer open.
        return ProcessInfo.processInfo.environment["DEMO_DRAWER"] == "1"
        #else
        return false
        #endif
    }()

    var body: some View {
        VStack(spacing: 0) {
            PopArtTitleBar("Wardrobe") {
                HStack(spacing: 16) {
                    Button {
                        toggleSearch()
                    } label: {
                        Image(systemName: searchActive ? "xmark" : "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.appOnHalftonePrimary)
                            .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                    }
                    .accessibilityLabel(searchActive ? "Close search" : "Search wardrobe")
                    NavigationLink {
                        SwipeHistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.appOnHalftonePrimary)
                            .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                    }
                    .accessibilityLabel("Full history")
                }
            }
            if searchActive {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ScrollView(.vertical, showsIndicators: false) {
                let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if searchActive && !trimmedQuery.isEmpty {
                    searchResultsSection(query: trimmedQuery)
                } else if historyViewModel.isLoading && historyViewModel.records.isEmpty {
                    ClosetSkeletonView()
                } else if closetIsEmpty {
                    emptyClosetState
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        railHeader("Tops & Jackets")
                        railSection(
                            records: viewModel.topRailRecords(from: historyViewModel.records),
                            labelPlacement: .nearHanger,
                            emptyTitle: "No tops yet",
                            emptyMessage: "Love something in the Feed and it'll be hanging here."
                        )
                        railHeader("Bottoms")
                            .padding(.top, 6)
                        railSection(
                            records: viewModel.bottomRailRecords(from: historyViewModel.records),
                            // Tag near the hanger (not reserved below) so the
                            // trousers get the full card height — bottoms
                            // render noticeably larger on the rail.
                            labelPlacement: .nearHanger,
                            emptyTitle: "No bottoms yet",
                            emptyMessage: "Like or love bottoms in the Feed to hang them here."
                        )
                        shelfSection
                        shoeSection
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 14)
                }
            }
            ClosetDrawerBar(
                collectionsCount: viewModel.collections.count,
                isOpen: drawerOpen,
                onToggle: toggleDrawer
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PopArtHalftoneBackground() }
        .overlay {
            if drawerOpen {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { toggleDrawer() }
                    CollectionsDrawerPanel(onClose: toggleDrawer)
                        .padding(.horizontal, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: drawerOpen)
        .toolbar(.hidden, for: .navigationBar)
        .task { await historyViewModel.loadIfNeeded() }
        .task { await viewModel.loadCollectionsIfNeeded() }
        .sheet(item: $selectedContext) { ctx in
            NavigationStack {
                ItemDetailView(
                    item: ctx.item,
                    swipeRecord: ctx.record,
                    onSwipeUpdated: { await historyViewModel.updateRecord(ctx.record, newAction: $0) },
                    isPresented: true
                )
            }
        }
    }

    private func toggleDrawer() {
        drawerOpen.toggle()
        ClosetHaptics.drawerThunk()
    }

    private func toggleSearch() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            searchActive.toggle()
        }
        if searchActive {
            searchFieldFocused = true
        } else {
            searchText = ""
            searchFieldFocused = false
        }
    }

    /// Nothing favorited at all (and not mid-load) — show the big CTA instead
    /// of four stacked per-section empty states.
    private var closetIsEmpty: Bool {
        !historyViewModel.isLoading
            && viewModel.allClosetRecords(from: historyViewModel.records).isEmpty
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black)
            TextField("Search your wardrobe", text: $searchText)
                .font(.appDisplay(size: 14))
                .foregroundStyle(Color.appPrimaryText)
                .focused($searchFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white))
        .overlay(Capsule().stroke(Color.black, lineWidth: 2.5))
        .background(Capsule().fill(Color.black).offset(x: 3, y: 3))
    }

    @ViewBuilder
    private func searchResultsSection(query: String) -> some View {
        let results = viewModel.searchClosetRecords(from: historyViewModel.records, query: query)
        if results.isEmpty {
            VStack(spacing: 14) {
                PopArtTag(rotation: -3) {
                    VStack(spacing: 3) {
                        Text("No matches")
                            .font(.appDisplay(size: 14))
                        Text("Nothing in your wardrobe matches \u{201C}\(query)\u{201D}.")
                            .font(.appDisplay(size: 11))
                            .opacity(0.7)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.appPrimaryText)
                    .frame(maxWidth: 230)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 70)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 105), spacing: 14)],
                spacing: 18
            ) {
                ForEach(results) { record in
                    searchResultCell(record)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
    }

    private func searchResultCell(_ record: SwipeRecord) -> some View {
        VStack(spacing: 5) {
            Group {
                if let item = record.item,
                   let pair = item.imageUrlPairs.first,
                   let url = URL(string: pair.primary) {
                    CachedAsyncImage(
                        url: url,
                        fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                        logContext: "closet-search",
                        tightCrop: true,
                        contentMode: .fit
                    )
                } else {
                    Rectangle().fill(Color.white.opacity(0.15))
                }
            }
            .frame(height: 110)
            VStack(spacing: 1) {
                Text(record.item?.name ?? "Item")
                    .font(.appDisplay(size: 10.5))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                if let brand = record.item?.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.appDisplay(size: 9))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .shadow(color: .black, radius: 0, x: 1.2, y: 1.2)
        }
        .contentShape(Rectangle())
        .onTapGesture { openDetail(for: record) }
        .addToCollectionMenu(recordId: record.id)
    }

    // MARK: - Whole-closet empty state

    private var emptyClosetState: some View {
        VStack(spacing: 20) {
            HangerShape()
                .stroke(
                    Color.black,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 110, height: 42)
                .shadow(color: .white.opacity(0.4), radius: 1)
            PopArtTag(rotation: -2.5) {
                VStack(spacing: 4) {
                    Text("Your closet is empty")
                        .font(.appDisplay(size: 17))
                    Text("Swipe right on pieces you like in the Feed and they'll hang themselves here.")
                        .font(.appDisplay(size: 12))
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.appPrimaryText)
                .frame(maxWidth: 240)
            }
            Button {
                tabRouter.selectedTab = .feed
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Browse the Feed")
                        .font(.appDisplay(size: 15))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(Capsule().fill(Color.appNeonPink))
                .overlay(Capsule().stroke(Color.black, lineWidth: 2.5))
                .background(Capsule().fill(Color.black).offset(x: 3, y: 3))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.bottom, 40)
    }

    // MARK: - Sections

    /// Comic sticker section label.
    private func railHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.appDisplay(size: 11))
            .tracking(0.8)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.appNeonPink))
            .overlay(Capsule().stroke(Color.black, lineWidth: 2))
            .background(Capsule().fill(Color.black).offset(x: 2, y: 2))
            .rotationEffect(.degrees(-1.5))
            .padding(.horizontal, 22)
    }

    @ViewBuilder
    private func railSection(
        records: [SwipeRecord],
        labelPlacement: ClosetLabelPlacement,
        emptyTitle: String,
        emptyMessage: String
    ) -> some View {
        if records.isEmpty {
            emptyRail(title: emptyTitle, message: emptyMessage)
        } else {
            ClosetRailView(records: records, labelPlacement: labelPlacement, onTap: openDetail)
        }
    }

    private func emptyRail(title: String, message: String) -> some View {
        ZStack(alignment: .top) {
            PopArtRod()
                .frame(height: 9)
                .padding(.horizontal, 6)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black)
                    .frame(width: 2, height: 26)
                PopArtTag(rotation: -3) {
                    VStack(spacing: 3) {
                        Text(title)
                            .font(.appDisplay(size: 14))
                        Text(message)
                            .font(.appDisplay(size: 11))
                            .opacity(0.7)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Color.appPrimaryText)
                    .frame(maxWidth: 230)
                }
            }
            .padding(.top, 5)
        }
        .frame(height: ClosetRailView.railHeight)
    }

    @ViewBuilder
    private var shelfSection: some View {
        let shelf = viewModel.shelfRecords(from: historyViewModel.records)
        if !shelf.isEmpty {
            railHeader("Bags & Accessories")
                .padding(.top, 6)
            ClosetShelfView(records: shelf, onTap: openDetail)
        }
    }

    @ViewBuilder
    private var shoeSection: some View {
        let shoes = viewModel.shoeRecords(from: historyViewModel.records)
        if !shoes.isEmpty {
            railHeader("Shoes")
                .padding(.top, 6)
            ShoeRackView(records: shoes, dragStyle: .wardrobeItem, onTap: openDetail)
        }
    }

    // MARK: - Detail navigation

    private func openDetail(for record: SwipeRecord) {
        if let item = record.item {
            selectedContext = HistoryDetailContext(id: record.id, item: item, record: record)
        } else {
            Task { await loadAndShowItem(id: record.itemId, record: record) }
        }
    }

    private func loadAndShowItem(id: String, record: SwipeRecord) async {
        do {
            let item = try await ItemService.fetchItem(id: id)
            await MainActor.run {
                selectedContext = HistoryDetailContext(id: record.id, item: item, record: record)
            }
        } catch {
            await MainActor.run { historyViewModel.errorMessage = error.localizedDescription }
        }
    }
}
