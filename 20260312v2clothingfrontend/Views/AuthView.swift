import AuthenticationServices
import SwiftUI

struct AuthView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var isShowingLogin = true

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                if isShowingLogin {
                    LoginView()
                } else {
                    RegisterView()
                }

                signInWithAppleSection

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isShowingLogin.toggle()
                    }
                } label: {
                    if isShowingLogin {
                        Text("Don't have an account? ")
                            .foregroundStyle(Color.appOnHalftoneSecondary)
                        + Text("Sign Up")
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appAccent)
                    } else {
                        Text("Already have an account? ")
                            .foregroundStyle(Color.appOnHalftoneSecondary)
                        + Text("Log In")
                            .fontWeight(.bold)
                            .foregroundStyle(Color.appAccent)
                    }
                }
                .font(.appDisplay(size: 15))
                .multilineTextAlignment(.center)
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var signInWithAppleSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                dividerLine
                Text("or")
                    .font(.appDisplay(size: 13))
                    .foregroundStyle(Color.appOnHalftoneSecondary)
                dividerLine
            }

            SignInWithAppleButton(isShowingLogin ? .signIn : .signUp) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await authViewModel.handleAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(authViewModel.isLoading)
        }
        .padding(.horizontal, 44)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.appOnHalftoneSecondary.opacity(0.4))
            .frame(height: 1)
    }
}
