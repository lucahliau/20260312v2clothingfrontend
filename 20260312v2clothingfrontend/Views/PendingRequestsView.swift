import SwiftUI

struct PendingRequestsView: View {
    @Environment(FriendsViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if viewModel.isLoadingPending, viewModel.pendingData == nil {
                    FriendsListSkeletonView()
                        .allowsHitTesting(false)
                        .accessibilityLabel("Loading requests")
                } else {
                    sections
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle("Pending")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPending()
        }
        .refreshable {
            await viewModel.loadPending()
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
    private var sections: some View {
        let data = viewModel.pendingData

        if data == nil
            || (data?.incomingFriendRequests.isEmpty == true
                && data?.outgoingFriendRequests.isEmpty == true) {
            ContentUnavailableView {
                Label("No pending requests", systemImage: "tray")
                    .font(.appDisplay(size: 20))
                    .foregroundStyle(Color.appOnHalftonePrimary)
            } description: {
                Text("You're all caught up.")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
            }
            .padding(.top, 24)
        } else {
            if let data, !data.incomingFriendRequests.isEmpty {
                sectionHeader("Incoming friend requests")
                VStack(spacing: 12) {
                    ForEach(data.incomingFriendRequests) { item in
                        incomingFriendRow(item)
                    }
                }
            }

            if let data, !data.outgoingFriendRequests.isEmpty {
                sectionHeader("Outgoing friend requests")
                VStack(spacing: 12) {
                    ForEach(data.outgoingFriendRequests) { item in
                        outgoingFriendRow(item)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.appDisplay(size: 13))
            .tracking(0.8)
            .foregroundStyle(Color.appOnHalftoneSecondary)
            .textCase(.uppercase)
    }

    private func incomingFriendRow(_ item: IncomingFriendRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                UserProfileView(username: item.user.username, preview: item.user)
            } label: {
                SocialUserPreviewRow(user: item.user, showChevron: true)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.acceptFriendRequest(fromUserId: item.user.id) }
                } label: {
                    Text("Accept")
                        .font(.appDisplay(size: 15))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.appAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await viewModel.declineFriendRequest(fromUserId: item.user.id) }
                } label: {
                    Text("Decline")
                        .font(.appDisplay(size: 15))
                        .foregroundStyle(Color.appPrimaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white)
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
        .popArtCardContainer()
    }

    private func outgoingFriendRow(_ item: OutgoingFriendRequestItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink {
                UserProfileView(username: item.user.username, preview: item.user)
            } label: {
                SocialUserPreviewRow(user: item.user, showChevron: false)
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.cancelOutgoingFriendRequest(userId: item.user.id) }
            } label: {
                Text("Cancel")
                    .font(.appDisplay(size: 14))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .popArtCardContainer()
    }
}
