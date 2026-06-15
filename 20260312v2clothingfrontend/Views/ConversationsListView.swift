import SwiftUI

struct ConversationsListView: View {
    @State private var viewModel = ConversationsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.conversations.isEmpty {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(0..<6, id: \.self) { _ in
                            ConversationRowSkeleton()
                                .popArtCardContainer()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .allowsHitTesting(false)
                .accessibilityLabel("Loading conversations")
            } else if viewModel.conversations.isEmpty {
                ContentUnavailableView {
                    Label("No messages yet", systemImage: "bubble.left.and.bubble.right")
                        .font(.appDisplay(size: 20))
                        .foregroundStyle(Color.appOnHalftonePrimary)
                } description: {
                    Text("Open a chat from your friends list to start a conversation.")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appOnHalftoneSecondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.conversations) { thread in
                            NavigationLink {
                                ConversationView(thread: thread)
                            } label: {
                                ConversationRow(thread: thread)
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
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
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
}

private struct ConversationRow: View {
    let thread: ConversationThread

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SocialAvatarView(urlString: thread.otherUser.avatarUrl, size: 52)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(thread.otherUser.username)
                        .font(.appDisplay(size: 17))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appPrimaryText)
                    Spacer(minLength: 8)
                    Text(relativeTime(thread.updatedAt))
                        .font(.appDisplay(size: 13))
                        .foregroundStyle(Color.appSecondaryText)
                }

                HStack(alignment: .top) {
                    Text(thread.lastMessage?.displayText ?? "No messages yet")
                        .font(.appDisplay(size: 15))
                        .foregroundStyle(Color.appSecondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if thread.unreadCount > 0 {
                        Text("\(thread.unreadCount)")
                            .font(.appDisplay(size: 12))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.92))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relativeTime(_ iso: String) -> String {
        let parsers: [ISO8601DateFormatter] = {
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return [withFrac, plain]
        }()
        guard let date = parsers.lazy.compactMap({ $0.date(from: iso) }).first else {
            return ""
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
