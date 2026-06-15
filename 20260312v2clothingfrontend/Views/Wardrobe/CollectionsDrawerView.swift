import SwiftUI

// MARK: - Closed drawer bar

/// The drawer front pinned at the bottom of the Closet — a pop-art card strip.
/// Tap (or flick up, or hover a dragged garment over it) to pull it open.
struct ClosetDrawerBar: View {
    var collectionsCount: Int
    var isOpen: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 5) {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 44, height: 5)
                HStack(spacing: 8) {
                    Text("Collections")
                        .font(.appDisplay(size: 15))
                        .foregroundStyle(Color.appPrimaryText)
                    if collectionsCount > 0 {
                        Text("\(collectionsCount)")
                            .font(.appDisplay(size: 11))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.appNeonPink))
                            .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
                    }
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText.opacity(0.7))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .popArtCardContainer()
        }
        .buttonStyle(.plain)
        .frame(height: 58)
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -16, !isOpen { onToggle() }
            }
        )
        // Spring-loaded: hovering a dragged garment over the closed drawer
        // pops it open so the drop can land on a collection stack.
        .dropDestination(for: WardrobeItemPayload.self) { _, _ in
            false
        } isTargeted: { hovering in
            if hovering, !isOpen { onToggle() }
        }
        .accessibilityLabel("Collections drawer")
        .accessibilityHint(isOpen ? "Closes the drawer" : "Opens the drawer")
    }
}

// MARK: - Open drawer panel

/// The pulled-open drawer: collections as folded stacks you can tap into or
/// drop dragged items onto.
struct CollectionsDrawerPanel: View {
    @Environment(WardrobeViewModel.self) private var viewModel
    @Environment(SwipeHistoryViewModel.self) private var historyViewModel
    var onClose: () -> Void

    @State private var showCreateAlert = false
    @State private var newCollectionName = ""
    @State private var detailCollection: Collection?
    @State private var targetedCollectionId: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            interior
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: -4)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous)
                .stroke(Color.black, lineWidth: PopArtCardStyle.strokeWidth)
        )
        .task { await viewModel.loadCollectionsIfNeeded() }
        .alert("New collection", isPresented: $showCreateAlert) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                Task {
                    if await viewModel.createCollection(named: newCollectionName) {
                        newCollectionName = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) { newCollectionName = "" }
        } message: {
            Text("Name your collection — drag items onto its stack to fill it.")
        }
        .sheet(item: $detailCollection) { collection in
            CollectionDetailSheet(collection: collection)
        }
    }

    private var header: some View {
        Button(action: onClose) {
            VStack(spacing: 5) {
                Capsule()
                    .fill(Color.black)
                    .frame(width: 44, height: 5)
                HStack(spacing: 8) {
                    Text("Collections")
                        .font(.appDisplay(size: 15))
                        .foregroundStyle(Color.appPrimaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText.opacity(0.7))
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.appNeonPink.opacity(0.14))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 2.5)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 56)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16, style: .continuous))
        .accessibilityLabel("Close drawer")
    }

    @ViewBuilder
    private var interior: some View {
        VStack(spacing: 6) {
            if viewModel.collections.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 22) {
                        ForEach(viewModel.collections) { collection in
                            stack(for: collection)
                        }
                        newStackButton
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                }
                Text("Long-press any item in your closet — or drag it onto a stack — to add it. Tap a stack to open it.")
                    .font(.appDisplay(size: 10))
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
            }
            if let error = viewModel.collectionsError {
                Text(error)
                    .font(.appDisplay(size: 11))
                    .foregroundStyle(Color.appNeonPink)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
            }
        }
        .frame(height: 214)
        .frame(maxWidth: .infinity)
    }

    private func stack(for collection: Collection) -> some View {
        CollectionStackView(
            collection: collection,
            previews: viewModel.collectionPreviews[collection.id],
            isTargeted: targetedCollectionId == collection.id
        )
        .onTapGesture { detailCollection = collection }
        .dropDestination(for: WardrobeItemPayload.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            Task {
                _ = await viewModel.addRecord(
                    withId: payload.recordId,
                    from: historyViewModel.records,
                    to: collection
                )
            }
            return true
        } isTargeted: { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                if hovering {
                    targetedCollectionId = collection.id
                } else if targetedCollectionId == collection.id {
                    targetedCollectionId = nil
                }
            }
        }
        .task(id: collection.id) {
            await viewModel.loadPreviewIfNeeded(for: collection)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("The drawer is empty")
                    .font(.appDisplay(size: 13))
                Text("Make a collection, then drag items onto its stack.")
                    .font(.appDisplay(size: 11))
                    .opacity(0.65)
            }
            .foregroundStyle(Color.appPrimaryText)
            .multilineTextAlignment(.center)
            Button {
                showCreateAlert = true
            } label: {
                Label("New collection", systemImage: "plus")
                    .font(.appDisplay(size: 13))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.appNeonPink))
                    .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                    .background(Capsule().fill(Color.black).offset(x: 2.5, y: 2.5))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newStackButton: some View {
        Button {
            showCreateAlert = true
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.black.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                    )
                    .frame(width: 86, height: 86)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.appNeonPink)
                    )
                Text("New")
                    .font(.appDisplay(size: 11))
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New collection")
    }
}

// MARK: - Collection stack

/// A collection as a folded pile: up to three item cutouts (or fabric-colored
/// folds while loading) with a paper name tag.
struct CollectionStackView: View {
    let collection: Collection
    let previews: [Item]?
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let previews, !previews.isEmpty {
                    ForEach(Array(previews.prefix(3).enumerated()), id: \.offset) { index, item in
                        cutout(for: item)
                            .offset(layerOffset(index))
                            .rotationEffect(.degrees(layerRotation(index)))
                    }
                } else {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(foldColor(index))
                            .frame(width: 64, height: 46)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.black.opacity(0.15), lineWidth: 1)
                            )
                            .offset(y: CGFloat(index) * -10)
                    }
                }
            }
            .frame(width: 92, height: 86, alignment: .bottom)

            PopArtTag(rotation: 2) {
                HStack(spacing: 5) {
                    Text(collection.name)
                        .font(.appDisplay(size: 11))
                        .lineLimit(1)
                    Text("\(collection._count?.items ?? 0)")
                        .font(.appDisplay(size: 10))
                        .opacity(0.65)
                }
                .foregroundStyle(Color.appPrimaryText)
                .frame(maxWidth: 96)
            }
        }
        .scaleEffect(isTargeted ? 1.12 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.appNeonPink, lineWidth: isTargeted ? 2.5 : 0)
                .padding(-6)
        )
        .accessibilityLabel("\(collection.name), \(collection._count?.items ?? 0) items")
        .accessibilityHint("Tap to open. Drop a dragged item to add it.")
    }

    @ViewBuilder
    private func cutout(for item: Item) -> some View {
        if let pair = item.imageUrlPairs.first, let url = URL(string: pair.primary) {
            CachedAsyncImage(
                url: url,
                fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                logContext: "closet-stack",
                tightCrop: true,
                contentMode: .fit
            )
            .frame(width: 58, height: 58)
        }
    }

    private func layerOffset(_ index: Int) -> CGSize {
        switch index {
        case 0: return CGSize(width: -12, height: 4)
        case 1: return CGSize(width: 12, height: -4)
        default: return CGSize(width: 0, height: -14)
        }
    }

    private func layerRotation(_ index: Int) -> Double {
        switch index {
        case 0: return -7
        case 1: return 5
        default: return -2
        }
    }

    /// Stable pastel folds derived from the collection name.
    private func foldColor(_ index: Int) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in collection.name.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        let hue = Double((hash >> UInt64(index * 8)) % 360) / 360.0
        return Color(hue: hue, saturation: 0.32, brightness: 0.82)
    }
}

// MARK: - Collection detail

struct CollectionDetailSheet: View {
    let collection: Collection
    @Environment(WardrobeViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var detail: CollectionDetail?
    @State private var isLoading = true
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ScrollView {
                        ExploreProductGridSkeletonView(cellCount: 6)
                            .padding(18)
                    }
                } else if let detail, !detail.items.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(detail.items) { collectionItem in
                                gridTile(for: collectionItem)
                            }
                        }
                        .padding(18)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Nothing in here yet")
                            .font(.appDisplay(size: 15))
                        Text("Drag items from the closet onto this collection's stack.")
                            .font(.appDisplay(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(collection.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete collection")
                }
            }
            .alert("Delete \"\(collection.name)\"?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.deleteCollection(collection)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The items themselves stay in your closet.")
            }
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appDisplay(size: 12))
                        .foregroundStyle(.red)
                        .padding(.bottom, 12)
                }
            }
        }
        .task { await loadDetail() }
    }

    private func gridTile(for collectionItem: CollectionItem) -> some View {
        VStack(spacing: 6) {
            Group {
                if let pair = collectionItem.item.imageUrlPairs.first,
                   let url = URL(string: pair.primary) {
                    CachedAsyncImage(
                        url: url,
                        fallbackUrl: pair.fallback.flatMap { URL(string: $0) },
                        logContext: "collection-detail",
                        tightCrop: true,
                        contentMode: .fit
                    )
                } else {
                    Rectangle().fill(Color.gray.opacity(0.15))
                }
            }
            .frame(height: 96)
            Text(collectionItem.item.name)
                .font(.appDisplay(size: 11))
                .lineLimit(1)
        }
        .contextMenu {
            Button(role: .destructive) {
                Task { await remove(collectionItem) }
            } label: {
                Label("Remove from collection", systemImage: "minus.circle")
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        do {
            detail = try await CollectionService.fetchCollection(id: collection.id)
            errorMessage = nil
        } catch {
            errorMessage = AuthErrorMapper.message(for: error)
        }
        isLoading = false
    }

    private func remove(_ collectionItem: CollectionItem) async {
        do {
            try await CollectionService.removeItemFromCollection(
                collectionId: collection.id,
                itemId: collectionItem.itemId
            )
            viewModel.invalidatePreview(for: collection.id)
            await viewModel.loadCollectionsIfNeeded(force: true)
            await loadDetail()
        } catch {
            errorMessage = AuthErrorMapper.message(for: error)
        }
    }
}
