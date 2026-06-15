import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedEmail.isEmpty && trimmedEmail.contains("@") && !isLoading
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Reset your password")
                    .font(.appDisplay(size: 22))
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Enter the email address for your account. If it’s registered, we’ll send a reset link.")
                    .font(.appDisplay(size: 14))
                    .foregroundStyle(Color.appSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(Color.appPrimaryText)
                        .authFormFieldChrome()
                        .disabled(didSucceed)

                    if didSucceed {
                        Text("If that email is registered, a reset link has been sent.")
                            .font(.appDisplay(size: 14))
                            .foregroundStyle(Color.appSecondaryText)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.appDisplay(size: 12))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if !didSucceed {
                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Send reset link")
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
                }
                .padding(20)
                .foregroundStyle(Color.appPrimaryText)
                .popArtCardContainer()

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .foregroundStyle(Color.appPrimaryText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AuthService.forgotPassword(email: trimmedEmail)
            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
