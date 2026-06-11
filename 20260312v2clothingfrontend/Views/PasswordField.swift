import SwiftUI

/// Secure text entry with the show/hide eye toggle every password field is
/// expected to have. Callers apply their own chrome (e.g. `authFormFieldChrome`).
struct PasswordField: View {
    let title: String
    @Binding var text: String
    var contentType: UITextContentType = .password

    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textContentType(contentType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
        }
    }
}
