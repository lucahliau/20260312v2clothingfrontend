import SwiftUI

struct ResetPasswordFromLinkView: View {
    let token: String
    var onDismiss: () -> Void

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    private var canSubmit: Bool {
        (8...128).contains(newPassword.count) && passwordsMatch && !isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Choose a new password")
                        .font(.appDisplay(size: 22))
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        SecureField("New password", text: $newPassword)
                            .textContentType(.newPassword)
                            .foregroundStyle(Color.appPrimaryText)
                            .authFormFieldChrome()

                        SecureField("Confirm password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .foregroundStyle(Color.appPrimaryText)
                            .authFormFieldChrome()

                        if !confirmPassword.isEmpty && !passwordsMatch {
                            Text("Passwords do not match")
                                .font(.appDisplay(size: 12))
                                .foregroundStyle(.red)
                        }

                        if !newPassword.isEmpty && newPassword.count < 8 {
                            Text("Password must be at least 8 characters.")
                                .font(.appDisplay(size: 12))
                                .foregroundStyle(.red)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.appDisplay(size: 12))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Update password")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.appAccent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!canSubmit)
                    }
                    .padding(20)
                    .foregroundStyle(Color.appPrimaryText)
                    .popArtCardContainer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
            .foregroundStyle(Color.appPrimaryText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
            }
            .alert("Password updated", isPresented: $showSuccessAlert) {
                Button("OK") {
                    onDismiss()
                }
            } message: {
                Text("Password has been reset. Please log in again.")
            }
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AuthService.resetPassword(token: token, password: newPassword)
            showSuccessAlert = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
