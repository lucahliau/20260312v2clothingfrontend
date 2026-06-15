import SwiftUI

struct SocialUserPreviewRow: View {
    let user: UserPreview
    var showChevron: Bool = true

    private var displayName: String {
        let parts = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }
        if parts.isEmpty { return user.username }
        return parts.joined(separator: " ").displayNormalizedTitle
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SocialAvatarView(urlString: user.avatarUrl, size: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.username)
                    .font(.appDisplay(size: 17))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.appPrimaryText)
                Text(displayName)
                    .font(.appDisplay(size: 14))
                    .foregroundStyle(Color.appSecondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SocialAvatarView: View {
    let urlString: String?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString.normalizedAsHTTPURLString) {
                CachedAsyncImage(
                    url: url,
                    logContext: "avatar",
                    failurePlaceholder: {
                        AnyView(avatarPlaceholder)
                    },
                    placeholder: { AnyView(avatarPlaceholder) }
                )
                .aspectRatio(contentMode: .fill)
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.black, lineWidth: 2)
        )
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .overlay {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(Color.appSecondaryText)
            }
    }
}
