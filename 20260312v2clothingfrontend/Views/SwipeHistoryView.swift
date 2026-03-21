import SwiftUI

/// Context for opening item detail from history (includes swipe record for interaction display/edit)
struct HistoryDetailContext: Identifiable {
    let id: String
    let item: Item
    let record: SwipeRecord
}

struct SwipeHistoryView: View {
    @Environment(SwipeHistoryViewModel.self) private var viewModel
    @State private var selectedContext: HistoryDetailContext?

    private static let sectionSpacing: CGFloat = 26
    private static let rowSpacing: CGFloat = 12
    private static let headerToRowsSpacing: CGFloat = 10

    var body: some View {
        Group {
            if viewModel.isLoading {
                SwipeHistorySkeletonView()
            } else if viewModel.records.isEmpty {
                ContentUnavailableView {
                    Label("No history", systemImage: "hand.draw")
                        .font(.appDisplay(size: 22))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                } description: {
                    Text("Swipe on items in the Feed to see them here.")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appOnHalftoneSecondary)
                }
            } else {
                historyScroll
            }
        }
        .navigationTitle("History")
        .task { await viewModel.loadIfNeeded() }
        .sheet(item: $selectedContext) { ctx in
            NavigationStack {
                ItemDetailView(
                    item: ctx.item,
                    swipeRecord: ctx.record,
                    onSwipeUpdated: { await viewModel.updateRecord(ctx.record, newAction: $0) },
                    isPresented: true
                )
            }
        }
        .background {
            PopArtHalftoneBackground()
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

    private var historyScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Self.sectionSpacing) {
                ForEach(viewModel.recordsBySection, id: \.0) { action, sectionRecords in
                    VStack(alignment: .leading, spacing: Self.headerToRowsSpacing) {
                        Text(sectionHeader(for: action))
                            .font(.appDisplay(size: 13))
                            .tracking(0.8)
                            .foregroundStyle(Color.appOnHalftoneSecondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 2)

                        LazyVStack(alignment: .leading, spacing: Self.rowSpacing) {
                            ForEach(sectionRecords) { record in
                                Button {
                                    openDetail(for: record)
                                } label: {
                                    SwipeHistoryRowView(record: record)
                                }
                                .buttonStyle(.plain)
                                .popArtCardContainer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func sectionHeader(for action: SwipeType) -> String {
        switch action {
        case .LOVE: return "Love"
        case .LIKE: return "Like"
        case .NEUTRAL: return "Neutral"
        case .DISLIKE: return "Dislike"
        }
    }

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
            await MainActor.run { viewModel.errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - History row (ghost until thumbnail loads)

private struct SwipeHistoryRowView: View {
    let record: SwipeRecord

    @State private var thumbReady = false

    private var needsThumb: Bool {
        guard let item = record.item,
              let pair = item.imageUrlPairs.first,
              let url = URL(string: pair.primary) else { return false }
        return !url.absoluteString.isEmpty
    }

    var body: some View {
        ZStack {
            SwipeHistoryRowSkeletonView()
                .opacity(thumbReady ? 0 : 1)
            rowContent
                .opacity(thumbReady ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.18), value: thumbReady)
        .onAppear {
            if !needsThumb {
                thumbReady = true
            }
        }
        .onChange(of: record.id) { _, _ in
            thumbReady = !needsThumb
        }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(record.item?.name ?? "Item")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appPrimaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                if let brand = record.item?.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.appDisplay(size: 15))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            actionBadge(record.action)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appSecondaryText)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let thumbSize = SwipeHistoryRowSkeletonView.thumbSize
        if let item = record.item,
           let pair = item.imageUrlPairs.first,
           let url = URL(string: pair.primary) {
            CachedAsyncImage(url: url, fallbackUrl: pair.fallback.flatMap { URL(string: $0) }, loadFinished: $thumbReady)
                .aspectRatio(contentMode: .fill)
                .frame(width: thumbSize, height: thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.gray.opacity(0.2))
                .frame(width: thumbSize, height: thumbSize)
        }
    }

    private func actionBadge(_ action: SwipeType) -> some View {
        Text(actionLabel(action))
            .font(.appDisplay(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor(action).opacity(0.2))
            .foregroundStyle(badgeColor(action))
            .clipShape(Capsule())
    }

    private func actionLabel(_ action: SwipeType) -> String {
        switch action {
        case .LOVE: return "Love"
        case .LIKE: return "Like"
        case .DISLIKE: return "Dislike"
        case .NEUTRAL: return "Neutral"
        }
    }

    private func badgeColor(_ action: SwipeType) -> Color {
        switch action {
        case .LOVE: return .red
        case .LIKE: return .green
        case .DISLIKE: return .orange
        case .NEUTRAL: return .gray
        }
    }
}
