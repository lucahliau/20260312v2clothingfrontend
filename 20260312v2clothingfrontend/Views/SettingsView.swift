import SwiftUI
import UIKit

private enum SettingsOverlay: Identifiable, Equatable {
    case dateOfBirth
    case gender
    case logout
    case error(String)
    case saved

    var id: String {
        switch self {
        case .dateOfBirth: return "dateOfBirth"
        case .gender: return "gender"
        case .logout: return "logout"
        case .error(let s): return "error:\(s)"
        case .saved: return "saved"
        }
    }
}

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(SettingsViewModel.self) private var viewModel

    @State private var activeOverlay: SettingsOverlay?
    @State private var tempDateOfBirth = Date()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var genderChoices: [(label: String, value: String)] {
        [("Not set", "")] + SettingsViewModel.genderOptions.map { ($0, $0) }
    }

    var body: some View {
        settingsBodyContent
            .navigationTitle("Settings")
            .task { await viewModel.loadProfileIfNeeded() }
            .onChange(of: viewModel.errorMessage) { _, new in
                settingsOnErrorMessageChange(new)
            }
            .onChange(of: viewModel.showSaveConfirmation) { _, new in
                settingsOnSaveConfirmationChange(new)
            }
            .onChange(of: activeOverlay) { _, new in
                settingsOnActiveOverlayChange(new)
            }
            .overlay {
                settingsOverlayLayer
            }
            .animation(.easeOut(duration: 0.22), value: activeOverlay?.id)
            .background {
                PopArtHalftoneBackground()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        resignFirstResponder()
                    }
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appAccent)
                }
            }
    }

    private var settingsBodyContent: some View {
        Group {
            if viewModel.isLoading && viewModel.lastProfileLoadAt == nil {
                SettingsProfileSkeletonView()
            } else {
                profileScroll
            }
        }
    }

    @ViewBuilder
    private var settingsOverlayLayer: some View {
        if let overlay = activeOverlay {
            settingsOverlayContent(overlay)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
        }
    }

    private func settingsOnErrorMessageChange(_ new: String?) {
        if let msg = new {
            withAnimation(.easeOut(duration: 0.22)) {
                activeOverlay = .error(msg)
            }
        }
    }

    private func settingsOnSaveConfirmationChange(_ new: Bool) {
        if new {
            withAnimation(.easeOut(duration: 0.22)) {
                activeOverlay = .saved
            }
        }
    }

    private func settingsOnActiveOverlayChange(_ new: SettingsOverlay?) {
        if case .dateOfBirth = new {
            tempDateOfBirth = viewModel.dateOfBirth ?? Date()
        }
    }

    private func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder
    private func settingsOverlayContent(_ overlay: SettingsOverlay) -> some View {
        switch overlay {
        case .dateOfBirth: dateOfBirthOverlay
        case .gender: genderOverlay
        case .logout: logoutOverlay
        case .error(let message): errorOverlay(message: message)
        case .saved: savedOverlay
        }
    }

    private var dateOfBirthOverlay: some View {
        PopArtCenteredModal(onTapOutside: { dismissOverlay() }) {
            PopArtModalCard(maxWidth: 380) {
                dateOfBirthOverlayCardContent
            }
        }
    }

    private var dateOfBirthOverlayCardContent: some View {
        VStack(spacing: 16) {
            PopArtModalTitle("Date of birth")
            dateOfBirthPicker
            dateOfBirthOverlayButtons
        }
    }

    private var dateOfBirthPicker: some View {
        DatePicker(
            "",
            selection: $tempDateOfBirth,
            in: ...Date.now,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(Color.appAccent)
        .accessibilityLabel("Date of Birth")
    }

    private var dateOfBirthOverlayButtons: some View {
        HStack(spacing: 12) {
            PopArtModalSecondaryButton(title: "Cancel") {
                dismissOverlay()
            }
            PopArtModalPrimaryButton(title: "Done") {
                viewModel.dateOfBirth = tempDateOfBirth
                dismissOverlay()
            }
        }
    }

    private var genderOverlay: some View {
        PopArtCenteredModal(onTapOutside: { dismissOverlay() }) {
            PopArtModalCard(maxWidth: 360) {
                genderOverlayCardContent
            }
        }
    }

    private var genderOverlayCardContent: some View {
        VStack(spacing: 14) {
            PopArtModalTitle("Gender")
            genderScroll
            PopArtModalSecondaryButton(title: "Close") {
                dismissOverlay()
            }
        }
    }

    private var genderScroll: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(genderChoices, id: \.label) { choice in
                    PopArtSelectionRow(
                        label: choice.label,
                        isSelected: viewModel.gender == choice.value
                    ) {
                        viewModel.gender = choice.value
                        dismissOverlay()
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    private var logoutOverlay: some View {
        PopArtConfirmDestructiveAlert(
            title: "Log out?",
            message: "Are you sure you want to log out?",
            confirmTitle: "Log Out",
            onCancel: { dismissOverlay() },
            onConfirm: {
                dismissOverlay()
                Task { await authViewModel.logout() }
            }
        )
    }

    private func errorOverlay(message: String) -> some View {
        PopArtMessageAlert(title: "Error", message: message) {
            viewModel.errorMessage = nil
            dismissOverlay()
        }
    }

    private var savedOverlay: some View {
        PopArtMessageAlert(title: "Saved", message: "Your profile has been updated.") {
            viewModel.showSaveConfirmation = false
            dismissOverlay()
        }
    }

    private func dismissOverlay() {
        withAnimation(.easeOut(duration: 0.22)) {
            activeOverlay = nil
        }
    }

    private var dateOfBirthDisplayText: String {
        guard let d = viewModel.dateOfBirth else { return "Not set" }
        return Self.displayDateFormatter.string(from: d)
    }

    private var genderDisplayText: String {
        viewModel.gender.isEmpty ? "Not set" : viewModel.gender
    }

    private var profileScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accountCard
                personalCard
                aboutCard
                saveCard
                logoutCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            VStack(alignment: .leading, spacing: 12) {
                settingsLabeledRow(title: "Email", value: viewModel.email)
                Divider().opacity(0.35)
                settingsLabeledRow(title: "Username", value: viewModel.username)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private var personalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Personal Info")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            personalInfoFields
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tint(Color.appAccent)
        .popArtCardContainer()
    }

    private var personalInfoFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsTextFieldRow(
                title: "First Name",
                prompt: "Given name",
                text: binding(\.firstName),
                contentType: .givenName
            )
            Divider().opacity(0.35)
            settingsTextFieldRow(
                title: "Last Name",
                prompt: "Family name",
                text: binding(\.lastName),
                contentType: .familyName
            )
            Divider().opacity(0.35)
            dateOfBirthRow
            Divider().opacity(0.35)
            genderRow
            Divider().opacity(0.35)
            settingsTextFieldRow(
                title: "Location",
                prompt: "City or region",
                text: binding(\.location),
                contentType: .addressCity
            )
        }
    }

    private var dateOfBirthRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date of Birth")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Button {
                resignFirstResponder()
                withAnimation(.easeOut(duration: 0.22)) {
                    activeOverlay = .dateOfBirth
                }
            } label: {
                HStack(alignment: .center) {
                    Text(dateOfBirthDisplayText)
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appPrimaryText)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date of Birth")
            .accessibilityValue(dateOfBirthDisplayText)
        }
    }

    private var genderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gender")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Button {
                resignFirstResponder()
                withAnimation(.easeOut(duration: 0.22)) {
                    activeOverlay = .gender
                }
            } label: {
                HStack(alignment: .center) {
                    Text(genderDisplayText)
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appPrimaryText)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Gender")
            .accessibilityValue(genderDisplayText)
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            TextField(
                "",
                text: binding(\.bio),
                prompt: Text("Tell others about your style…")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appSecondaryText),
                axis: .vertical
            )
            .lineLimit(4...8)
            .font(.appDisplay(size: 17))
            .foregroundStyle(Color.appPrimaryText)
            .frame(minHeight: 100, alignment: .topLeading)
            .multilineTextAlignment(.leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private var saveCard: some View {
        Button {
            resignFirstResponder()
            Task { await viewModel.saveProfile() }
        } label: {
            HStack {
                Spacer()
                if viewModel.isSaving {
                    ProgressView()
                        .tint(Color.appAccent)
                } else {
                    Text("Save Changes")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appAccent)
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .popArtCardContainer()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSaving)
    }

    private var logoutCard: some View {
        Button {
            resignFirstResponder()
            withAnimation(.easeOut(duration: 0.22)) {
                activeOverlay = .logout
            }
        } label: {
            Text("Log Out")
                .font(.appDisplay(size: 17))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(18)
                .popArtCardContainer()
        }
        .buttonStyle(.plain)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<SettingsViewModel, String>) -> Binding<String> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    private func settingsLabeledRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Text(value)
                .font(.appDisplay(size: 17))
                .foregroundStyle(Color.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingsTextFieldRow(
        title: String,
        prompt: String,
        text: Binding<String>,
        contentType: UITextContentType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            TextField(
                "",
                text: text,
                prompt: Text(prompt)
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appSecondaryText)
            )
            .textContentType(contentType)
            .font(.appDisplay(size: 17))
            .foregroundStyle(Color.appPrimaryText)
        }
    }
}
