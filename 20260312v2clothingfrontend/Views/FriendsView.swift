import SwiftUI

struct FriendsView: View {
    @Environment(FriendsViewModel.self) private var viewModel
    @FocusState private var searchFieldFocused: Bool

    private var trimmedQuery: String {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 0) {
            PopArtTitleBar("Friends") {
                NavigationLink {
                    ConversationsListView()
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .shadow(color: .black, radius: 0, x: 1.5, y: 1.5)
                }
                .accessibilityLabel("Messages")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    searchBarContent(binding: $viewModel.searchText, isFocused: $searchFieldFocused)

                    if trimmedQuery.isEmpty {
                        homeContent
                    } else {
                        searchResultsContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadIfNeeded()
            await NotificationsManager.checkFriendsHotItems()
            if ConnectivityMonitor.shared.allowsHeavyPrefetch {
                viewModel.prewarmAvatars()
            }
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.onSearchTextChanged()
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    searchFieldFocused = false
                }
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appAccent)
            }
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            pendingRequestsRow

            NavigationLink {
                FriendsListView()
            } label: {
                listChip(title: "All friends", systemImage: "heart")
            }
            .buttonStyle(.plain)

            Text("Your friends")
                .font(.appDisplay(size: 13))
                .tracking(0.8)
                .foregroundStyle(Color.appOnHalftoneSecondary)
                .textCase(.uppercase)

            if viewModel.isLoadingFriends {
                FriendsListSkeletonView()
                    .allowsHitTesting(false)
                    .accessibilityLabel("Loading friends")
            } else if viewModel.friends.isEmpty {
                ContentUnavailableView {
                    Label("No friends yet", systemImage: "person.2")
                        .font(.appDisplay(size: 20))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                } description: {
                    Text("Search above to find people, or check pending requests.")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appOnHalftoneSecondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.friends) { user in
                        NavigationLink {
                            ConversationView(friend: user)
                        } label: {
                            SocialUserPreviewRow(user: user)
                        }
                        .buttonStyle(.plain)
                        .popArtCardContainer()
                    }
                }
            }
        }
    }

    private func listChip(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.appAccent)
            Text(title)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appPrimaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .popArtCardContainer()
    }

    private var pendingRequestsRow: some View {
        NavigationLink {
            PendingRequestsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tray.full")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pending requests")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appPrimaryText)
                    Text("Friend requests")
                        .font(.appDisplay(size: 14))
                        .foregroundStyle(Color.appSecondaryText)
                }
                Spacer()
                if viewModel.pendingBadgeCount > 0 {
                    Text("\(viewModel.pendingBadgeCount)")
                        .font(.appDisplay(size: 13))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appAccent)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .popArtCardContainer()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if viewModel.isSearching {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    FriendsSearchRowSkeleton()
                        .popArtCardContainer()
                }
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Searching users")
        } else if viewModel.searchResults.isEmpty {
            ContentUnavailableView {
                Label("No users found", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.appDisplay(size: 20))
                    .foregroundStyle(Color.appOnHalftonePrimary)
            } description: {
                Text("Try another name or username.")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
            }
            .padding(.top, 8)
        } else {
            VStack(spacing: 12) {
                ForEach(viewModel.searchResults) { user in
                    NavigationLink {
                        UserProfileView(username: user.username, preview: user)
                    } label: {
                        SocialUserPreviewRow(user: user)
                    }
                    .buttonStyle(.plain)
                    .popArtCardContainer()
                }
            }
        }
    }

    private func searchBarContent(binding: Binding<String>, isFocused: FocusState<Bool>.Binding) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appSecondaryText)
            TextField(
                "",
                text: binding,
                prompt: Text("Search people").foregroundStyle(Color(white: 0.42))
            )
            .font(.appDisplay(size: 17))
            .foregroundStyle(Color.appPrimaryText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused(isFocused)
            .submitLabel(.search)
            .accessibilityLabel("Search people")
            .onSubmit {
                searchFieldFocused = false
            }
            if searchFieldFocused {
                Button("Done") {
                    searchFieldFocused = false
                }
                .font(.appDisplay(size: 15))
                .foregroundStyle(Color.appAccent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .popArtCardContainer()
    }
}
