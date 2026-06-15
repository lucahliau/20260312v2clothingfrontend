import SwiftUI

struct FriendsListView: View {
    @State private var items: [UserPreview] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ScrollView {
                    FriendsListSkeletonView()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .allowsHitTesting(false)
                .accessibilityLabel("Loading list")
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("No friends yet", systemImage: "person.2")
                        .font(.appDisplay(size: 20))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                } description: {
                    Text("Accepted friend requests appear here.")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appOnHalftoneSecondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { user in
                            NavigationLink {
                                UserProfileView(username: user.username, preview: user)
                            } label: {
                                SocialUserPreviewRow(user: user)
                            }
                            .buttonStyle(.plain)
                            .popArtCardContainer()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
        .overlay {
            if let message = errorMessage {
                PopArtMessageAlert(title: "Error", message: message) {
                    errorMessage = nil
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.22), value: errorMessage)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await SocialService.fetchFriends(limit: 100, offset: 0)
            items = page.items
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }
}
