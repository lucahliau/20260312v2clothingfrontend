import SwiftUI

struct RegisterView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Account")
                .font(.appDisplay(size: 28))
                .fontWeight(.bold)

            VStack(spacing: 14) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Color.appPrimaryText)
                    .authFormFieldChrome()

                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Color.appPrimaryText)
                    .authFormFieldChrome()

                SecureField("Password", text: $password)
                    .textContentType(.newPassword)
                    .foregroundStyle(Color.appPrimaryText)
                    .authFormFieldChrome()

                SecureField("Confirm Password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .foregroundStyle(Color.appPrimaryText)
                    .authFormFieldChrome()

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords do not match")
                        .font(.appDisplay(size: 12))
                        .foregroundStyle(.red)
                }

                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.appDisplay(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await authViewModel.register(email: email, username: username, password: password) }
                } label: {
                    Group {
                        if authViewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Sign Up")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.appAccent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(email.isEmpty || username.isEmpty || !passwordsMatch || authViewModel.isLoading)
            }
            .padding(20)
            .foregroundStyle(Color.appPrimaryText)
            .popArtCardContainer()
        }
        .padding(.horizontal, 24)
        .padding(.trailing, PopArtCardStyle.shadowOffset)
        .padding(.bottom, PopArtCardStyle.shadowOffset)
    }
}
