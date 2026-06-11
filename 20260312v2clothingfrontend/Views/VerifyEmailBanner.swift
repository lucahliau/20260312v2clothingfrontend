import SwiftUI

/// Verify-later nag: shown above the tab bar until the user verifies their
/// email (or dismisses it for this launch). Re-checks status when the app
/// foregrounds — the user usually just tapped the link in Mail/Safari.
struct VerifyEmailBanner: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if authViewModel.needsEmailVerification && !authViewModel.verifyBannerDismissed {
            HStack(spacing: 10) {
                Image(systemName: "envelope.badge")
                    .foregroundStyle(Color.appAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Verify your email")
                        .font(.appDisplay(size: 14))
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.appDisplay(size: 12))
                        .foregroundStyle(Color.appSecondaryText)
                }
                Spacer(minLength: 8)
                if authViewModel.resendState != .sent {
                    Button {
                        Task { await authViewModel.resendVerificationEmail() }
                    } label: {
                        Text(authViewModel.resendState == .sending ? "Sending…" : "Resend")
                            .font(.appDisplay(size: 13))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(authViewModel.resendState == .sending)
                }
                Button {
                    authViewModel.verifyBannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .foregroundStyle(Color.appPrimaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.appPrimaryText.opacity(0.12))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await authViewModel.refreshVerificationStatus() }
                }
            }
        }
    }

    private var subtitle: String {
        authViewModel.resendState == .sent
            ? "Link sent — check your inbox."
            : "Confirm your address to secure your account."
    }
}
