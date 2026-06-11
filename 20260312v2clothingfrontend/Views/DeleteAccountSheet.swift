import SwiftUI

/// In-app account deletion (App Store 5.1.1(v)). Typed-username confirmation
/// works for every account type, including Sign in with Apple users who have
/// no password.
struct DeleteAccountSheet: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss

    let username: String

    @State private var confirmationText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var canDelete: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == username.lowercased() && !isDeleting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This permanently deletes your account.")
                        .font(.appDisplay(size: 16))
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Your profile and photo")
                        bullet("Your swipes and feed history")
                        bullet("Your collections and wardrobe")
                        bullet("Your friends and messages")
                    }

                    Text("Everything is removed immediately and can't be recovered.")
                        .font(.appDisplay(size: 13))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type your username (\(username)) to confirm:")
                            .font(.appDisplay(size: 13))
                            .foregroundStyle(.secondary)
                        TextField("Username", text: $confirmationText)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.appDisplay(size: 16))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.primary.opacity(0.1))
                            )
                    }
                    .padding(.top, 4)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.appDisplay(size: 13))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await performDelete() }
                    } label: {
                        Group {
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Delete my account").fontWeight(.semibold)
                            }
                        }
                        .font(.appDisplay(size: 16))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canDelete ? Color.red : Color.red.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canDelete)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.red.opacity(0.7))
                .padding(.top, 2)
            Text(text)
                .font(.appDisplay(size: 14))
        }
    }

    private func performDelete() async {
        isDeleting = true
        errorMessage = nil
        if let error = await authViewModel.deleteAccount() {
            errorMessage = error
            isDeleting = false
        }
        // On success the auth gate flips and the whole hierarchy (including
        // this sheet) is replaced by the login screen.
    }
}
