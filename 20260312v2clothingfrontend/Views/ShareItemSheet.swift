import SwiftUI

/// "Send to a friend" sheet: pick a friend, we open (or create) the 1:1
/// conversation and send the item as a product message (plus an optional
/// note). Presented from the item detail view and the brand grid.
struct ShareItemSheet: View {
    let item: Item

    @Environment(\.dismiss) private var dismiss

    @State private var friends: [UserPreview] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var note = ""
    @State private var sendingFriendId: String?
    @State private var sentFriendIds: Set<String> = []
    @State private var sendError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    itemSummary
                    noteField
                    friendsSection
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .navigationTitle("Send to a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appAccent)
                }
            }
            .task { await loadFriends() }
            .overlay {
                if let message = sendError {
                    PopArtMessageAlert(title: "Couldn't send", message: message) {
                        sendError = nil
                    }
                    .zIndex(100)
                }
            }
        }
    }

    private var itemSummary: some View {
        HStack(spacing: 12) {
            Group {
                if let url = item.firstOriginalImageURL {
                    CachedAsyncImage(url: url, fallbackUrl: item.secondOriginalImageURL)
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.25))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(Color.appSecondaryText)
                        }
                }
            }
            .frame(width: 64, height: 64)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black, lineWidth: 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name.displayNormalizedTitle)
                    .font(.appDisplay(size: 15))
                    .foregroundStyle(Color.appPrimaryText)
                    .lineLimit(2)
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand.displayNormalizedTitle)
                        .font(.appDisplay(size: 13))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var noteField: some View {
        TextField(
            "",
            text: $note,
            prompt: Text("Add a note (optional)").foregroundStyle(Color(white: 0.42))
        )
        .font(.appDisplay(size: 16))
        .foregroundStyle(Color.appPrimaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
    }

    @ViewBuilder
    private var friendsSection: some View {
        Text("Friends".uppercased())
            .font(.appDisplay(size: 12))
            .tracking(1.1)
            .foregroundStyle(Color.appSecondaryText)

        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading friends…")
                    .font(.appDisplay(size: 15))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
        } else if let loadError {
            VStack(spacing: 10) {
                Text(loadError)
                    .font(.appDisplay(size: 15))
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await loadFriends() }
                }
                .font(.appDisplay(size: 15))
                .foregroundStyle(Color.appAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if friends.isEmpty {
            ContentUnavailableView {
                Label("No friends yet", systemImage: "person.2")
                    .font(.appDisplay(size: 18))
                    .foregroundStyle(Color.appPrimaryText)
            } description: {
                Text("Add friends in the Friends tab to share finds.")
                    .font(.appDisplay(size: 15))
                    .foregroundStyle(Color.appSecondaryText)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(friends) { friend in
                    friendRow(friend)
                }
            }
        }
    }

    private func friendRow(_ friend: UserPreview) -> some View {
        let isSending = sendingFriendId == friend.id
        let isSent = sentFriendIds.contains(friend.id)
        return Button {
            Task { await send(to: friend) }
        } label: {
            HStack(spacing: 12) {
                initialsAvatar(for: friend)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: friend))
                        .font(.appDisplay(size: 16))
                        .foregroundStyle(Color.appPrimaryText)
                        .lineLimit(1)
                    Text("@\(friend.username)")
                        .font(.appDisplay(size: 13))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isSending {
                    ProgressView()
                } else if isSent {
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .font(.appDisplay(size: 14))
                        .foregroundStyle(Color.appNeonPink)
                        .labelStyle(.titleAndIcon)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(isSending || isSent)
    }

    private func initialsAvatar(for friend: UserPreview) -> some View {
        let first = friend.firstName?.first.map(String.init) ?? ""
        let last = friend.lastName?.first.map(String.init) ?? ""
        let fallback = friend.username.first.map(String.init) ?? "?"
        let initials = (first + last).isEmpty ? fallback : first + last
        return Text(initials.uppercased())
            .font(.appDisplay(size: 14))
            .foregroundStyle(Color.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.appPopArtBlue))
            .overlay(Circle().stroke(Color.black, lineWidth: 2))
    }

    private func displayName(for friend: UserPreview) -> String {
        let full = [friend.firstName, friend.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? friend.username : full
    }

    private func loadFriends() async {
        isLoading = true
        loadError = nil
        do {
            let response = try await SocialService.fetchFriends(limit: 100)
            friends = response.items
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func send(to friend: UserPreview) async {
        sendingFriendId = friend.id
        defer { sendingFriendId = nil }
        do {
            let conversation = try await MessagingService.openOrCreateConversation(userId: friend.id)
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await MessagingService.sendMessage(
                conversationId: conversation.id,
                content: trimmedNote.isEmpty ? nil : trimmedNote,
                itemId: item.id
            )
            sentFriendIds.insert(friend.id)
        } catch {
            sendError = error.localizedDescription
        }
    }
}
