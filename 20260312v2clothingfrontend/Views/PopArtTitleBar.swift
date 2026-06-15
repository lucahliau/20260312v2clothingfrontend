import SwiftUI

/// Compact pop-art replacement for the system large-title nav bar. The system
/// bar leaves a tall dead zone under the notch; this sits right below the
/// status bar instead — comic-bold white title with a hard black offset
/// (matches the card extrusion), plus optional trailing actions.
///
/// Use with `.toolbar(.hidden, for: .navigationBar)` on the tab's root view;
/// pushed views keep the regular bar (and back button) automatically.
struct PopArtTitleBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        let theme = Theme.current
        return HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.appDisplay(size: 28))
                .foregroundStyle(theme.onBackgroundPrimary)
                .shadow(color: theme.ink, radius: 0, x: theme.titleShadowOffset, y: theme.titleShadowOffset)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

extension PopArtTitleBar where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}
