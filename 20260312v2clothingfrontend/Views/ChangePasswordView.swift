import SwiftUI

struct ChangePasswordView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    private var canSubmit: Bool {
        !currentPassword.isEmpty
            && newPassword.count >= 8
            && passwordsMatch
            && newPassword != currentPassword
            && !isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if didSucceed {
                        successContent
                    } else {
                        formContent
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Text("For your security, changing your password signs out all your other devices.")
            .font(.appDisplay(size: 13))
            .foregroundStyle(.secondary)

        fieldBox {
            PasswordField(title: "Current password", text: $currentPassword, contentType: .password)
        }
        fieldBox {
            PasswordField(title: "New password", text: $newPassword, contentType: .newPassword)
        }
        fieldBox {
            PasswordField(title: "Confirm new password", text: $confirmPassword, contentType: .newPassword)
        }

        if !newPassword.isEmpty && newPassword.count < 8 {
            ruleText("At least 8 characters.", isError: true)
        } else if !confirmPassword.isEmpty && !passwordsMatch {
            ruleText("Passwords do not match.", isError: true)
        } else if !newPassword.isEmpty && newPassword == currentPassword {
            ruleText("Your new password must be different.", isError: true)
        } else {
            ruleText("At least 8 characters.", isError: false)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(.appDisplay(size: 13))
                .foregroundStyle(.red)
        }

        Button {
            Task { await submit() }
        } label: {
            Group {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text("Change password").fontWeight(.semibold)
                }
            }
            .font(.appDisplay(size: 16))
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSubmit ? Color.appAccent : Color.appAccent.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canSubmit)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var successContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("Password changed")
                .font(.appDisplay(size: 18))
                .fontWeight(.semibold)
            Text("All your other devices were signed out. This device stays logged in.")
                .font(.appDisplay(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func fieldBox<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.appDisplay(size: 16))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1))
            )
    }

    private func ruleText(_ text: String, isError: Bool) -> some View {
        Text(text)
            .font(.appDisplay(size: 12))
            .foregroundStyle(isError ? .red : .secondary)
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        if let error = await authViewModel.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword
        ) {
            errorMessage = error
        } else {
            didSucceed = true
        }
        isWorking = false
    }
}
