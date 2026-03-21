import SwiftUI

struct AuthView: View {
    @State private var isShowingLogin = true

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                if isShowingLogin {
                    LoginView()
                } else {
                    RegisterView()
                }

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
}
