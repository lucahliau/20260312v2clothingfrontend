import SwiftUI

/// The Wardrobe ("Saved") tab — every liked/loved item in one searchable,
/// sortable, filterable grid on the app's halftone wallpaper. Saved brands sit
/// in a strip on top; collections live in the pull-open drawer at the bottom.
struct ClosetView: View {
    @Environment(SwipeHistoryViewModel.self) private var historyViewModel
    @Environment(WardrobeViewModel.self) private var viewModel
    @Environment(ExploreViewModel.self) private var exploreModel
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

    private let gridColumns = [GridItem(.adaptive(minimum: 105), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            PopArtTitleBar("Saved") {
                HStack(spacing: 16) {
                    Button {
                        toggleSearch()
                    } label: {
                        Image(systemName: searchActive ? "xmark" : "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.appOnHalftonePrimary)
                            .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                    }
                    .accessibilityLabel(searchActive ? "Close search" : "Search saved items")
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
                VStack(alignment: .leading, spacing: 12) {
                    savedBrandsSection
                    savedItemsSection
                }
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
            .refreshable { await refresh() }
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
        .overlay(alignment: .top) {
            if let toast = viewModel.toastMessage {
                toastView(toast)
                    .padding(.top, 48)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if let message = historyViewModel.errorMessage {
                PopArtMessageAlert(title: "Error", message: message) {
                    historyViewModel.errorMessage = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: drawerOpen)
        .animation(.easeOut(duration: 0.22), value: viewModel.toastMessage)
        .animation(.easeOut(duration: 0.22), value: historyViewModel.errorMessage)
        .toolbar(.hidden, for: .navigationBar)
        .task { await historyViewModel.loadLikedIfNeeded() }
        .task { await viewModel.loadCollectionsIfNeeded() }
        .task { await exploreModel.refreshSavedBrands() }
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

    private func refresh() async {
        async let liked: Void = historyViewModel.reloadLiked()
        async let collections: Void = viewModel.loadCollectionsIfNeeded(force: true)
        async let brands: Void = exploreModel.refreshSavedBrands()
        _ = await (liked, collections, brands)
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

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.black)
            TextField("Search saved items", text: $searchText)
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

    // MARK: - Saved brands

    /// Same strip as Explore's (hearted brands from `/brands/favorites`,
    /// owned by `ExploreViewModel`); hidden while searching.
    @ViewBuilder
    private var savedBrandsSection: some View {
        if !exploreModel.savedBrands.isEmpty, trimmedQuery.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Saved brands")
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
                    .padding(.horizontal, 18)
                    .padding(.bottom, 3)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.appDisplay(size: 13))
            .tracking(0.8)
            .foregroundStyle(Color.appOnHalftoneSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, 18)
    }

    // MARK: - Saved items

    @ViewBuilder
    private var savedItemsSection: some View {
        let all = historyViewModel.likedRecords
        if all.isEmpty {
            if historyViewModel.isLoadingLiked {
                ClosetSkeletonView()
            } else if let error = historyViewModel.likedErrorMessage {
                loadErrorState(error)
            } else {
                emptyClosetState
            }
        } else {
            let visible = viewModel.visibleRecords(from: all, query: trimmedQuery)
            if historyViewModel.likedErrorMessage != nil {
                staleBanner
            }
            controlsRow(all: all, visibleCount: visible.count)
            if visible.isEmpty {
                noMatchesState
            } else {
                LazyVGrid(columns: gridColumns, spacing: 18) {
                    ForEach(visible) { record in
                        savedItemCell(record)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Sort + filter controls

    private func controlsRow(all: [SwipeRecord], visibleCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    sortMenu
                    brandMenu(options: viewModel.brandOptions(from: all))
                    typeMenu(options: viewModel.typeOptions(from: all))
                    Button {
                        viewModel.lovedOnly.toggle()
                    } label: {
                        controlChip(
                            title: "Loved",
                            systemImage: viewModel.lovedOnly ? "heart.fill" : "heart",
                            isActive: viewModel.lovedOnly,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Loved only")
                    .accessibilityAddTraits(viewModel.lovedOnly ? .isSelected : [])
                    if viewModel.hasActiveFilters {
                        Button {
                            viewModel.clearFilters()
                        } label: {
                            controlChip(title: "Clear", systemImage: "xmark", isActive: false, showsChevron: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear filters")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 3)
            }
            Text(countLabel(visible: visibleCount, total: all.count))
                .font(.appDisplay(size: 12))
                .foregroundStyle(Color.appOnHalftoneSecondary)
                .padding(.horizontal, 18)
        }
    }

    private func countLabel(visible: Int, total: Int) -> String {
        let noun = total == 1 ? "item" : "items"
        if visible == total { return "\(total) \(noun)" }
        return "\(visible) of \(total) \(noun)"
    }

    private var sortMenu: some View {
        @Bindable var viewModel = viewModel
        return Menu {
            Picker("Sort", selection: $viewModel.sort) {
                ForEach(WardrobeSort.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            controlChip(
                title: viewModel.sort.shortName,
                systemImage: "arrow.up.arrow.down",
                isActive: viewModel.sort != .recentlyLiked
            )
        }
        .accessibilityLabel("Sort: \(viewModel.sort.displayName)")
    }

    private func brandMenu(options: [WardrobeFilterOption]) -> some View {
        @Bindable var viewModel = viewModel
        let selected = options.first { $0.id == viewModel.brandFilter }
        return Menu {
            Picker("Brand", selection: $viewModel.brandFilter) {
                Text("All brands").tag(String?.none)
                ForEach(options) { option in
                    Text("\(option.label) (\(option.count))").tag(String?.some(option.id))
                }
            }
        } label: {
            controlChip(
                title: selected?.label ?? (viewModel.brandFilter == nil ? "Brand" : "Brand: none left"),
                systemImage: "tag",
                isActive: viewModel.brandFilter != nil
            )
        }
        .accessibilityLabel("Filter by brand")
    }

    private func typeMenu(options: [WardrobeFilterOption]) -> some View {
        @Bindable var viewModel = viewModel
        let selected = options.first { $0.id == viewModel.typeFilter }
        return Menu {
            Picker("Type", selection: $viewModel.typeFilter) {
                Text("All types").tag(String?.none)
                ForEach(options) { option in
                    Text("\(option.label) (\(option.count))").tag(String?.some(option.id))
                }
            }
        } label: {
            controlChip(
                title: selected?.label ?? (viewModel.typeFilter == nil ? "Type" : "Type: none left"),
                systemImage: "tshirt",
                isActive: viewModel.typeFilter != nil
            )
        }
        .accessibilityLabel("Filter by type")
    }

    /// Capsule chip in the same sticker language as the saved-brand chips;
    /// active filters flip to the neon fill used by the app's section tags.
    private func controlChip(
        title: String,
        systemImage: String,
        isActive: Bool,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.appDisplay(size: 13))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(isActive ? Color.white : Color.appPrimaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(isActive ? Color.appNeonPink : Color.white))
        .overlay(Capsule().stroke(Color.black, lineWidth: 2))
        .background(Capsule().fill(Color.black).offset(x: 2, y: 2))
        .contentShape(Capsule())
    }

    // MARK: - Grid cell

    private func savedItemCell(_ record: SwipeRecord) -> some View {
        VStack(spacing: 5) {
            itemImage(for: record)
                .frame(height: 110)
                .overlay(alignment: .topTrailing) {
                    if record.action == .LOVE {
                        loveSticker
                    }
                }
            VStack(spacing: 1) {
                if let brand = record.item?.brand, !brand.isEmpty {
                    Text(brand.displayNormalizedTitle)
                        .font(.appDisplay(size: 9))
                        .foregroundStyle(Color.appOnHalftonePrimary.opacity(0.9))
                        .lineLimit(1)
                }
                Text(record.item?.name ?? "Item")
                    .font(.appDisplay(size: 10.5))
                    .foregroundStyle(Color.appOnHalftonePrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
                if let price = record.item?.priceDouble {
                    Text("$\(Int(price.rounded()))")
                        .font(.appDisplay(size: 10.5))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                }
            }
            .shadow(color: .black, radius: 0, x: 1.2, y: 1.2)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { openDetail(for: record) }
        .draggable(WardrobeItemPayload(recordId: record.id)) {
            itemImage(for: record)
                .frame(width: 110, height: 130)
        }
        .contextMenu {
            AddToCollectionMenuItems(recordId: record.id)
            Section {
                Button {
                    Task {
                        await historyViewModel.updateRecord(
                            record,
                            newAction: record.action == .LOVE ? .LIKE : .LOVE
                        )
                    }
                } label: {
                    if record.action == .LOVE {
                        Label("Change to Like", systemImage: "hand.thumbsup")
                    } else {
                        Label("Love it", systemImage: "heart.fill")
                    }
                }
                Button(role: .destructive) {
                    Task { await remove(record) }
                } label: {
                    Label("Remove from Saved", systemImage: "minus.circle")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel(for: record))
    }

    @ViewBuilder
    private func itemImage(for record: SwipeRecord) -> some View {
        if let item = record.item,
           let pair = item.imageUrlPairs.first,
           let url = URL(string: pair.primary) {
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                logContext: "closet-grid",
                failurePlaceholder: { AnyView(ClosetView.missingImagePlaceholder) },
                tightCrop: true,
                contentMode: .fit
            )
        } else {
            Self.missingImagePlaceholder
        }
    }

    /// Static stand-in for an item whose image is missing or failed to load —
    /// the item itself always stays in the grid.
    private static var missingImagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.15))
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.7))
            )
            .accessibilityLabel("Image unavailable")
    }

    private var loveSticker: some View {
        ZStack {
            Circle()
                .fill(Color.appNeonPink)
                .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                .frame(width: 22, height: 22)
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .accessibilityLabel("Loved")
    }

    private func accessibilityLabel(for record: SwipeRecord) -> String {
        var parts = [record.item?.name ?? "Item"]
        if let brand = record.item?.brand, !brand.isEmpty { parts.append("by \(brand)") }
        if let price = record.item?.priceDouble { parts.append("$\(Int(price.rounded()))") }
        if record.action == .LOVE { parts.append("loved") }
        return parts.joined(separator: ", ")
    }

    private func remove(_ record: SwipeRecord) async {
        if await historyViewModel.removeFromWardrobe(record) {
            viewModel.showToast("Removed from Saved")
        }
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.appDisplay(size: 13))
            .foregroundStyle(Color.appPrimaryText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().stroke(Color.black, lineWidth: 2.5))
            .background(Capsule().fill(Color.black).offset(x: 3, y: 3))
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - States

    private var noMatchesState: some View {
        VStack(spacing: 14) {
            PopArtTag(rotation: -3) {
                VStack(spacing: 3) {
                    Text("No matches")
                        .font(.appDisplay(size: 14))
                    Text(noMatchesMessage)
                        .font(.appDisplay(size: 11))
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.appPrimaryText)
                .frame(maxWidth: 230)
            }
            if viewModel.hasActiveFilters {
                pillButton("Clear filters", systemImage: "xmark") {
                    viewModel.clearFilters()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
        .padding(.bottom, 30)
    }

    private var noMatchesMessage: String {
        if !trimmedQuery.isEmpty {
            let suffix = viewModel.hasActiveFilters ? " with these filters" : ""
            return "Nothing saved matches \u{201C}\(trimmedQuery)\u{201D}\(suffix)."
        }
        return "Nothing saved matches these filters."
    }

    /// The load failed and there is nothing cached to show.
    private func loadErrorState(_ message: String) -> some View {
        VStack(spacing: 20) {
            PopArtTag(rotation: -2.5) {
                VStack(spacing: 4) {
                    Text("Couldn't load your saved items")
                        .font(.appDisplay(size: 17))
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.appDisplay(size: 12))
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.appPrimaryText)
                .frame(maxWidth: 240)
            }
            pillButton("Retry", systemImage: "arrow.clockwise") {
                Task { await historyViewModel.reloadLiked() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.bottom, 40)
    }

    /// A refresh failed but an earlier copy is on screen.
    private var staleBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.appNeonPink)
            Text("Couldn't refresh — showing your last saved copy.")
                .font(.appDisplay(size: 12))
                .foregroundStyle(Color.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Retry") {
                Task { await historyViewModel.reloadLiked() }
            }
            .font(.appDisplay(size: 13))
            .foregroundStyle(Color.appNeonPink)
            .disabled(historyViewModel.isLoadingLiked)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .popArtCardContainer()
        .padding(.horizontal, 18)
        .padding(.bottom, 4)
    }

    private func pillButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
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
    }

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
                    Text("Nothing saved yet")
                        .font(.appDisplay(size: 17))
                    Text("Swipe right on pieces you like in the Feed and they'll show up here.")
                        .font(.appDisplay(size: 12))
                        .opacity(0.7)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color.appPrimaryText)
                .frame(maxWidth: 240)
            }
            pillButton("Browse the Feed", systemImage: "rectangle.stack.fill") {
                tabRouter.selectedTab = .feed
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.bottom, 40)
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
