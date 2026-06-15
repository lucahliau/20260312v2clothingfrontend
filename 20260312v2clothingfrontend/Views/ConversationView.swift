import SwiftUI

struct ConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ConversationViewModel
    @State private var draftText = ""
    @State private var showProductPicker = false
    @State private var lastLoadOlderAt: Date = .distantPast
    init(friend: UserPreview) {
        _viewModel = State(wrappedValue: ConversationViewModel(conversationId: nil, otherUser: friend))
    }

    init(thread: ConversationThread) {
        _viewModel = State(wrappedValue: ConversationViewModel(conversationId: thread.id, otherUser: thread.otherUser))
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if viewModel.isLoadingOlder {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.9)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }

                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(
                            message: message,
                            isFromMe: viewModel.isFromMe(message),
                            showTimestamp: false,
                            onDelete: viewModel.isFromMe(message)
                                ? { Task { await viewModel.deleteMessage(id: message.id) } }
                                : nil
                        )
                        .id(message.id)
                        .onAppear {
                            if index == 0 {
                                triggerLoadOlder()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.id) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    SocialAvatarView(urlString: viewModel.otherUser.avatarUrl, size: 32)
                    Text(viewModel.otherUser.username)
                        .font(.appDisplay(size: 17))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appOnHalftonePrimary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                UserModerationMenu(
                    userId: viewModel.otherUser.id,
                    username: viewModel.otherUser.username
                ) {
                    // Blocking hides the conversation server-side; leave it.
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composerBar()
        }
        .task {
            await viewModel.loadThreadIfNeeded()
        }
        .sheet(isPresented: $showProductPicker) {
            ProductPickerSheet { item in
                showProductPicker = false
                Task { @MainActor in
                    _ = await viewModel.sendProduct(itemId: item.id)
                }
            }
        }
        .overlay {
            if let message = viewModel.errorMessage {
                PopArtMessageAlert(
                    title: "Error",
                    message: message,
                    onDismiss: { viewModel.errorMessage = nil },
                    retryTitle: "Retry",
                    onRetry: {
                        viewModel.errorMessage = nil
                        Task { await viewModel.retryLoadThread() }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.22), value: viewModel.errorMessage)
        .overlay {
            if viewModel.isLoadingInitial && viewModel.messages.isEmpty {
                ConversationThreadSkeletonView()
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func triggerLoadOlder() {
        let now = Date()
        guard now.timeIntervalSince(lastLoadOlderAt) > 0.6 else { return }
        guard viewModel.hasMore, !viewModel.isLoadingOlder, !viewModel.isLoadingInitial else { return }
        lastLoadOlderAt = now
        Task {
            await viewModel.loadOlder()
        }
    }

    private func composerBar() -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                showProductPicker = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canInteract ? Color.appAccent : Color.gray.opacity(0.45))
            }
            .disabled(!canInteract)
            .accessibilityLabel("Share a product")

            TextField(
                "Message",
                text: $draftText,
                axis: .vertical
            )
            .font(.appDisplay(size: 17))
            .foregroundStyle(Color.appPrimaryText)
            .lineLimit(1...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
            Button {
                let t = draftText
                Task { @MainActor in
                    let ok = await viewModel.sendText(t)
                    if ok { draftText = "" }
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.appAccent : Color.gray.opacity(0.45))
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        viewModel.canSendMessage && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Allow composing while the initial thread loads; sends are gated in the view model via `ensureConversationId`.
    private var canInteract: Bool {
        viewModel.canSendMessage
    }
}

// MARK: - Product picker

private struct ProductPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var items: [Item] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    let onPick: (Item) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("Search for a product", systemImage: "tshirt")
                            .font(.appDisplay(size: 18))
                    } description: {
                        Text("Type a name or brand to find items to send.")
                            .font(.appDisplay(size: 15))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List(items) { item in
                        Button {
                            onPick(item)
                        } label: {
                            HStack(spacing: 12) {
                                productThumb(item)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name.displayNormalizedTitle)
                                        .font(.appDisplay(size: 16))
                                        .foregroundStyle(Color.appPrimaryText)
                                        .multilineTextAlignment(.leading)
                                    if let b = item.brand, !b.isEmpty {
                                        Text(b.displayNormalizedTitle)
                                            .font(.appDisplay(size: 14))
                                            .foregroundStyle(Color.appSecondaryText)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Send a product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.appDisplay(size: 17))
                }
            }
            .searchable(text: $query, prompt: Text("Search catalog"))
            .onChange(of: query) { _, newValue in
                scheduleSearch(newValue)
            }
            .task {
                await performSearch(trimmed: "")
            }
        }
        .presentationDetents([.large])
    }

    private func scheduleSearch(_ raw: String) {
        searchTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            await performSearch(trimmed: trimmed)
        }
    }

    private func performSearch(trimmed: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await ItemService.fetchItemsPage(
                page: 1,
                limit: 40,
                search: trimmed.isEmpty ? nil : trimmed
            )
            items = page.items
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }

    @ViewBuilder
    private func productThumb(_ item: Item) -> some View {
        if let url = item.firstOriginalImageURL {
            CachedAsyncImage(
                url: url,
                fallbackUrl: item.secondOriginalImageURL,
                logContext: "picker",
                failurePlaceholder: { AnyView(placeholderThumb) },
                placeholder: { AnyView(placeholderThumb) }
            )
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholderThumb
                .frame(width: 56, height: 56)
        }
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(Color.appSecondaryText)
            }
    }
}
