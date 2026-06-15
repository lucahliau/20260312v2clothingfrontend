import SwiftUI

struct UserProfileView: View {
    let username: String
    var preview: UserPreview?

    @Environment(FriendsViewModel.self) private var friendsViewModel
    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionInFlight = false
    @State private var showRemoveFriendConfirm = false

    var body: some View {
        Group {
            if isLoading && profile == nil {
                ScrollView {
                    if let preview {
                        HStack(spacing: 14) {
                            SocialAvatarView(urlString: preview.avatarUrl, size: 72)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(preview.username)
                                    .font(.appDisplay(size: 18))
                                    .foregroundStyle(Color.appOnHalftonePrimary)
                                Text("Loading…")
                                    .font(.appDisplay(size: 14))
                                    .foregroundStyle(Color.appOnHalftoneSecondary)
                            }
                            Spacer()
                        }
                        .padding(18)
                        .popArtCardContainer()
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    FriendsListSkeletonView()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .allowsHitTesting(false)
                .accessibilityLabel("Loading profile")
            } else if let p = profile {
                profileScroll(profile: p)
            } else {
                ContentUnavailableView {
                    Label("Profile unavailable", systemImage: "person.crop.circle.badge.xmark")
                        .font(.appDisplay(size: 20))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                } description: {
                    Text("This user could not be loaded.")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appOnHalftoneSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PopArtHalftoneBackground()
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let p = profile {
                ToolbarItem(placement: .topBarTrailing) {
                    UserModerationMenu(userId: p.id, username: p.username) {
                        Task {
                            await loadProfile()
                            await friendsViewModel.refreshAll()
                        }
                    }
                }
            }
        }
        .task {
            await loadProfile()
        }
        .refreshable {
            await loadProfile()
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
        .overlay {
            if showRemoveFriendConfirm {
                PopArtConfirmDestructiveAlert(
                    title: "Remove friend",
                    message: "Remove this person from your friends list?",
                    confirmTitle: "Remove",
                    onCancel: { showRemoveFriendConfirm = false },
                    onConfirm: {
                        showRemoveFriendConfirm = false
                        Task { await performRemoveFriend() }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(101)
            }
        }
        .animation(.easeOut(duration: 0.22), value: showRemoveFriendConfirm)
    }

    private func profileScroll(profile: UserProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard(profile: profile)

                if let bio = profile.bio, !bio.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About")
                            .font(.appDisplay(size: 13))
                            .tracking(0.8)
                            .foregroundStyle(Color.appOnHalftoneSecondary)
                            .textCase(.uppercase)
                        Text(bio)
                            .font(.appDisplay(size: 17))
                            .foregroundStyle(Color.appPrimaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(18)
                    .popArtCardContainer()
                }

                relationshipActions(profile: profile)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func headerCard(profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            SocialAvatarView(urlString: profile.avatarUrl, size: 96)

            VStack(spacing: 6) {
                Text(displayFullName(for: profile))
                    .font(.appDisplay(size: 22))
                    .foregroundStyle(Color.appPrimaryText)
                    .multilineTextAlignment(.center)
                Text("@\(profile.username)")
                    .font(.appDisplay(size: 15))
                    .foregroundStyle(Color.appSecondaryText)
            }

            if let priv = profile.profileIsPrivate, priv {
                Text("Private account")
                    .font(.appDisplay(size: 13))
                    .foregroundStyle(Color.appSecondaryText)
            }

            HStack {
                Spacer(minLength: 0)
                statBlock(value: profile.friendsCount ?? 0, label: "Friends")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .popArtCardContainer()
    }

    private func statBlock(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.appDisplay(size: 20))
                .fontWeight(.semibold)
                .foregroundStyle(Color.appPrimaryText)
            Text(label)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
        }
    }

    @ViewBuilder
    private func relationshipActions(profile: UserProfile) -> some View {
        if let rel = profile.relationship {
            VStack(alignment: .leading, spacing: 12) {
                Text("Actions")
                    .font(.appDisplay(size: 13))
                    .tracking(0.8)
                    .foregroundStyle(Color.appOnHalftoneSecondary)
                    .textCase(.uppercase)

                friendButtons(rel: rel, userId: profile.id)
            }
        }
    }

    @ViewBuilder
    private func friendButtons(rel: UserRelationship, userId: String) -> some View {
        switch rel.friendship {
        case "none":
            primaryPillButton(title: "Add friend", systemImage: "heart") {
                Task { await sendFriendRequest(userId: userId) }
            }
        case "pending_out":
            secondaryPillButton(title: "Friend request sent", systemImage: "paperplane") {
                Task { await cancelFriendRequest(userId: userId) }
            }
        case "pending_in":
            HStack(spacing: 12) {
                primaryPillButton(title: "Accept", systemImage: "checkmark.circle") {
                    Task { await acceptFriendRequest(fromUserId: userId) }
                }
                secondaryPillButton(title: "Decline", systemImage: "xmark.circle") {
                    Task { await declineFriendRequest(fromUserId: userId) }
                }
            }
        case "friends":
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.appAccent)
                    Text("Friends")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appPrimaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)

                secondaryPillButton(title: "Remove friend", systemImage: "person.crop.circle.badge.minus") {
                    showRemoveFriendConfirm = true
                }
            }
        default:
            EmptyView()
        }
    }

    private func primaryPillButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.appDisplay(size: 17))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.appAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(actionInFlight)
        .opacity(actionInFlight ? 0.55 : 1)
    }

    private func secondaryPillButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.appDisplay(size: 17))
            .foregroundStyle(Color.appPrimaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(actionInFlight)
        .opacity(actionInFlight ? 0.55 : 1)
    }

    private func displayFullName(for profile: UserProfile) -> String {
        let parts = [profile.firstName, profile.lastName].compactMap { $0 }.filter { !$0.isEmpty }
        if parts.isEmpty { return profile.username }
        return parts.joined(separator: " ").displayNormalizedTitle
    }

    private func loadProfile() async {
        errorMessage = nil
        if profile == nil {
            isLoading = true
        }
        defer { isLoading = false }
        do {
            profile = try await SocialService.fetchUserProfile(username: username)
        } catch {
            errorMessage = error.localizedDescription
            profile = nil
        }
    }

    private func sendFriendRequest(userId: String) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            _ = try await SocialService.sendFriendRequest(userId: userId)
            await loadProfile()
            await friendsViewModel.refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelFriendRequest(userId: String) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            _ = try await SocialService.cancelFriendRequest(userId: userId)
            await loadProfile()
            await friendsViewModel.refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func acceptFriendRequest(fromUserId: String) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            _ = try await SocialService.acceptFriendRequest(fromUserId: fromUserId)
            await loadProfile()
            await friendsViewModel.refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func declineFriendRequest(fromUserId: String) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            _ = try await SocialService.declineFriendRequest(fromUserId: fromUserId)
            await loadProfile()
            await friendsViewModel.refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRemoveFriend() async {
        guard let id = profile?.id else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            _ = try await SocialService.removeFriend(userId: id)
            await loadProfile()
            await friendsViewModel.refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
