import SwiftUI

/// The Fitting Room — the outfit composer behind the Closet's door. The old
/// wardrobe layout lives on here: a draggable rail, the 4-slot mannequin, and
/// the shoe rack as the drag source for the shoes slot.
struct FittingRoomView: View {
    @Environment(SwipeHistoryViewModel.self) private var historyViewModel
    @Environment(WardrobeViewModel.self) private var viewModel

    @State private var selectedContext: HistoryDetailContext?

    private static let rackHeight: CGFloat = HangerCardView.cardHeight + 8

    var body: some View {
        VStack(spacing: 0) {
            categoryBar
            rackSection
            Spacer(minLength: 0)
            mannequinSection
            Spacer(minLength: 0)
            shoeSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle("Fitting Room")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.outfit.isEmpty {
                    Button("Clear") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            viewModel.clearOutfit()
                        }
                    }
                    .font(.appDisplay(size: 15))
                    .foregroundStyle(Color.appOnHalftonePrimary)
                }
            }
        }
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

    // MARK: - Sections

    private var rackSection: some View {
        let records = viewModel.hangerRecords(from: historyViewModel.records)
        return Group {
            if records.isEmpty {
                emptyRackState
            } else {
                HangerCarouselView(records: records, onTap: openDetail)
            }
        }
        .frame(height: Self.rackHeight)
    }

    private var mannequinSection: some View {
        MannequinView(
            outfit: viewModel.outfit,
            onTapEquipped: handleTapEquipped,
            onDropRecord: handleDropRecord
        )
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var shoeSection: some View {
        let shoes = viewModel.shoeRecords(from: historyViewModel.records)
        if !shoes.isEmpty {
            ShoeRackView(records: shoes, dragStyle: .outfitSlot, onTap: openDetail)
        }
    }

    private var emptyRackState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hanger")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.appOnHalftonePrimary.opacity(0.7))
            Text("Nothing to try on")
                .font(.appDisplay(size: 15))
                .foregroundStyle(Color.appOnHalftonePrimary)
            Text("Love or like items in the Feed, then dress the mannequin here.")
                .font(.appDisplay(size: 12))
                .foregroundStyle(Color.appOnHalftoneSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Filter chips

    private var categoryBar: some View {
        @Bindable var vm = viewModel
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WardrobeCategory.closetRailCases, id: \.self) { category in
                    chip(for: category, selected: vm.selectedCategory == category) {
                        withAnimation(.easeOut(duration: 0.22)) {
                            vm.selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    private func chip(for category: WardrobeCategory, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(category.displayName)
                .font(.appDisplay(size: 13))
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.appPrimaryText : Color.appOnHalftonePrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(selected ? Color.white : Color.white.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(selected ? 0 : 0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Drop / tap handlers

    private func handleDropRecord(_ slot: OutfitSlot, _ recordId: String) {
        let allCandidates = viewModel.hangerRecords(from: historyViewModel.records)
            + viewModel.shoeRecords(from: historyViewModel.records)
        guard let record = allCandidates.first(where: { $0.id == recordId }) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            viewModel.place(record, in: slot)
        }
        ClosetHaptics.place()
    }

    private func handleTapEquipped(_ slot: OutfitSlot) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            viewModel.remove(slot)
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
