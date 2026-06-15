import SwiftUI

struct MessageBubble: View {
    let message: ConversationMessage
    let isFromMe: Bool
    var showTimestamp: Bool = false
    var onDelete: (() -> Void)?

    @State private var resolvedItem: Item?
    @State private var itemLoadFailed = false
    @State private var loadItemTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 6) {
            Group {
                if message.isDeleted {
                    deletedPlaceholder
                } else {
                    VStack(alignment: isFromMe ? .trailing : .leading, spacing: 8) {
                        if let text = message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            textBubble(text: text)
                        }
                        if message.item != nil || message.itemId != nil {
                            productCard
                        }
                        if !hasTextContent && message.item == nil && message.itemId == nil {
                            emptyFallback
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)

            if showTimestamp {
                Text(formattedTime(message.createdAt))
                    .font(.appDisplay(size: 12))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
            }
        }
        .onAppear {
            resolveItemIfNeeded()
        }
        .onChange(of: message.id) { _, _ in
            itemLoadFailed = false
            resolvedItem = nil
            resolveItemIfNeeded()
        }
        .onDisappear {
            loadItemTask?.cancel()
        }
    }

    private var deletedPlaceholder: some View {
        Text("This message was deleted")
            .font(.appDisplay(size: 15))
            .foregroundStyle(Color.appSecondaryText)
            .italic()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
    }

    private func textBubble(text: String) -> some View {
        Text(text)
            .font(.appDisplay(size: 16))
            .foregroundStyle(isFromMe ? Color.white : Color.appPrimaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isFromMe ? Color.appAccent : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.black.opacity(isFromMe ? 0 : 0.15), lineWidth: isFromMe ? 0 : 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .contextMenu {
                if isFromMe, let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    private var hasTextContent: Bool {
        guard let t = message.content?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !t.isEmpty
    }

    private var emptyFallback: some View {
        Text("Message")
            .font(.appDisplay(size: 14))
            .foregroundStyle(Color.appSecondaryText)
            .italic()
    }

    @ViewBuilder
    private var productCard: some View {
        let item = message.item ?? resolvedItem
        if let item {
            DMProductCard(item: item, isFromMe: isFromMe, onDelete: isFromMe ? onDelete : nil)
        } else if itemLoadFailed {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text("Couldn’t load this product.")
                        .font(.appDisplay(size: 14))
                        .foregroundStyle(Color.appPrimaryText)
                }
                Button {
                    itemLoadFailed = false
                    resolveItemIfNeeded(force: true)
                } label: {
                    Text("Try again")
                        .font(.appDisplay(size: 15))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.appAccent.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .popArtCardContainer()
            .frame(maxWidth: 280, alignment: isFromMe ? .trailing : .leading)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.85)
                Text("Loading product…")
                    .font(.appDisplay(size: 14))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .padding(12)
            .popArtCardContainer()
            .frame(maxWidth: 280, alignment: isFromMe ? .trailing : .leading)
        }
    }

    private func resolveItemIfNeeded(force: Bool = false) {
        if message.item != nil { return }
        guard let iid = message.itemId, !iid.isEmpty else { return }
        if itemLoadFailed, !force { return }
        loadItemTask?.cancel()
        loadItemTask = Task {
            await MainActor.run {
                itemLoadFailed = false
            }
            do {
                let fetched = try await ItemService.fetchItem(id: iid)
                await MainActor.run {
                    resolvedItem = fetched
                    itemLoadFailed = false
                }
            } catch {
                await MainActor.run {
                    resolvedItem = nil
                    itemLoadFailed = true
                }
            }
        }
    }

    private func formattedTime(_ iso: String) -> String {
        let parsers: [ISO8601DateFormatter] = {
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return [withFrac, plain]
        }()
        let date = parsers.lazy.compactMap { $0.date(from: iso) }.first
        guard let date else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Instagram-style product attachment

private struct DMProductCard: View {
    let item: Item
    let isFromMe: Bool
    var onDelete: (() -> Void)?

    @State private var imageLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image area
            ZStack(alignment: .bottomLeading) {
                productImage
                    .frame(height: 200)
                    .clipped()

                LinearGradient(
                    colors: [.black.opacity(0.55), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .bottom)

                if let brand = item.brand, !brand.isEmpty {
                    Text(brand.displayNormalizedTitle)
                        .font(.appDisplay(size: 13))
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .padding(12)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.name.displayNormalizedTitle)
                    .font(.appDisplay(size: 17))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let price = item.priceDouble {
                    Text(formatPrice(price))
                        .font(.appDisplay(size: 16))
                        .foregroundStyle(Color.appAccent)
                } else if let p = item.price, !p.isEmpty {
                    Text(p)
                        .font(.appDisplay(size: 16))
                        .foregroundStyle(Color.appAccent)
                }

                if let urlString = item.sourceUrl, let url = URL(string: urlString), !urlString.isEmpty {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "bag.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Shop on website")
                                .font(.appDisplay(size: 16))
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        .frame(maxWidth: 280, alignment: isFromMe ? .trailing : .leading)
        .clipShape(RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius)
                .stroke(Color.black, lineWidth: PopArtCardStyle.strokeWidth)
        )
        .background(
            RoundedRectangle(cornerRadius: PopArtCardStyle.cornerRadius)
                .fill(Color.black)
                .offset(x: PopArtCardStyle.shadowOffset, y: PopArtCardStyle.shadowOffset)
        )
        .contextMenu {
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var productImage: some View {
        if let url = item.firstOriginalImageURL {
            CachedAsyncImage(
                url: url,
                fallbackUrl: item.secondOriginalImageURL,
                logContext: "dm_product",
                loadFinished: $imageLoaded
            )
            .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.appSecondaryText)
                }
        }
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
