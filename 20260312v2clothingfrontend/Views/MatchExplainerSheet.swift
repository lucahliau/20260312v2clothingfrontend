import SwiftUI

/// Tap-to-open explainer for the corner match badge. Shows why the recommender
/// surfaced this item (personalized / novelty / random / cold start) and, for
/// personalized cards, the top liked items that built the matching cluster.
///
/// `onPickContributor` lets the parent push an `ItemDetailView` for one of the
/// contributor thumbnails without this sheet needing to know about navigation.
struct MatchExplainerSheet: View {
    let match: FeedMatch
    let onClose: () -> Void
    var onPickContributor: ((MatchContributor) -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    reasonSection
                    if !match.topContributors.isEmpty {
                        contributorsSection
                    }
                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.white)
            .navigationTitle("Match details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bucketColor)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
            Text(headerTitle)
                .font(.appDisplay(size: 22))
                .foregroundStyle(Color.appPrimaryText)
        }
    }

    private var headerTitle: String {
        switch match.source {
        case .personalized:
            let pct = match.scorePct ?? 0
            let label: String
            switch match.bucket {
            case .high: label = "Strong match"
            case .medium: label = "Possible match"
            case .low: label = "Long shot"
            case .none: label = "Match"
            }
            return "\(label) · \(pct)%"
        case .novelty:
            return "Exploration · NEW"
        case .random:
            return "Random pick"
        case .coldStart:
            return "Getting to know you"
        }
    }

    private var bucketColor: Color {
        switch match.source {
        case .personalized:
            switch match.bucket {
            case .high: return .green
            case .medium: return .yellow
            case .low: return .red
            case .none: return .gray
            }
        case .novelty: return .blue
        case .random, .coldStart: return .gray
        }
    }

    // MARK: - Reason

    @ViewBuilder
    private var reasonSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why you're seeing this")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
                .textCase(.uppercase)
            Text(reasonText)
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reasonText: String {
        switch match.source {
        case .personalized:
            return "Personalized — it sits inside one of the interest clusters we built from items you liked and loved."
        case .novelty:
            return "Exploration — picked because it's different from your usual taste, in case you want to broaden your feed."
        case .random:
            return "Random pick — slotted in for diversity so the feed stays fresh."
        case .coldStart:
            return "You haven't swiped enough yet for personalization. Like and dislike a few items and your feed will start to learn."
        }
    }

    // MARK: - Contributors

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Because you liked")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
                .textCase(.uppercase)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(match.topContributors.prefix(3)) { contributor in
                        contributorTile(contributor)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func contributorTile(_ contributor: MatchContributor) -> some View {
        let tile = VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.gray.opacity(0.12)
                if let url = contributor.imageURL {
                    CachedAsyncImage(
                        url: url,
                        logContext: "match-contributor"
                    )
                    .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1)
            )
            Text(contributor.name)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appPrimaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 110, alignment: .leading)
        }

        if let onPick = onPickContributor {
            Button {
                onPick(contributor)
            } label: {
                tile
            }
            .buttonStyle(.plain)
        } else {
            tile
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Debug")
                .font(.appDisplay(size: 12))
                .foregroundStyle(Color.appSecondaryText)
                .textCase(.uppercase)
            Group {
                Text("source: \(match.source.rawValue)")
                if let idx = match.clusterIndex { Text("clusterIndex: \(idx)") }
                if let sim = match.clusterSim { Text(String(format: "clusterSim: %.4f", sim)) }
                if let pct = match.scorePct { Text("scorePct: \(pct)") }
                if let b = match.bucket { Text("bucket: \(b.rawValue)") }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color.appSecondaryText)
        }
        .padding(.top, 10)
    }
    #endif
}
