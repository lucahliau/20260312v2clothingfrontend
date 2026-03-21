import SwiftUI

struct LoginView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome Back")
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

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .foregroundStyle(Color.appPrimaryText)
                    .authFormFieldChrome()

                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(.appDisplay(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await authViewModel.login(email: email, password: password) }
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
                .disabled(email.isEmpty || password.isEmpty || authViewModel.isLoading)
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
