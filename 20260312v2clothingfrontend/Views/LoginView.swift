import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var identifier = ""
    @State private var password = ""
    @State private var showForgotPassword = false

    private var canSubmitLogin: Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !authViewModel.isLoading
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome Back")
                .font(.appDisplay(size: 28))
                .fontWeight(.bold)

            VStack(spacing: 14) {
                TextField("Email or username", text: $identifier)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Color.appPrimaryText)
                    .authFormFieldChrome()

                PasswordField(title: "Password", text: $password, contentType: .password)
                    .foregroundStyle(Color.appPrimaryText)
                    .authFormFieldChrome()

                Button {
                    showForgotPassword = true
                } label: {
                    Text("Forgot password?")
                        .font(.appDisplay(size: 14))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)

                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.appDisplay(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await authViewModel.login(identifier: identifier, password: password) }
                } label: {
                    Group {
                        if authViewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Log In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSubmitLogin)
            }
            .padding(20)
            .foregroundStyle(Color.appPrimaryText)
            .popArtCardContainer()
        }
        .padding(.horizontal, 24)
        .padding(.trailing, PopArtCardStyle.shadowOffset)
        .padding(.bottom, PopArtCardStyle.shadowOffset)
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }
}
