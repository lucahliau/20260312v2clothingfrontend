import SwiftUI

struct AuthView: View {
    @State private var isShowingLogin = true

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

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
                    Text("Don't have an account? **Sign Up**")
                } else {
                    Text("Already have an account? **Log In**")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()
        }
    }
}
