import OSLog
import PhotosUI
import SwiftUI
import UIKit

private let settingsAvatarLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clothing", category: "SettingsAvatar")

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
    @Environment(FeedViewModel.self) private var feedViewModel

    @State private var activeOverlay: SettingsOverlay?
    @State private var tempDateOfBirth = Date()
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraPicker = false
    @State private var capturedCameraImage: UIImage?
    @State private var showChangePassword = false
    @State private var showDeleteAccount = false

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
        VStack(spacing: 0) {
            PopArtTitleBar("Settings")
            settingsBodyContent
        }
            .toolbar(.hidden, for: .navigationBar)
            .task { await viewModel.loadProfileIfNeeded() }
            .onChange(of: photoPickerItem) { _, new in
                Task { await handlePhotoLibrarySelection(new) }
            }
            .onChange(of: capturedCameraImage) { _, new in
                guard let new else { return }
                Task {
                    await viewModel.uploadAvatarFromUIImage(new)
                    capturedCameraImage = nil
                }
            }
            .sheet(isPresented: $showCameraPicker) {
                CameraImagePicker(capturedImage: $capturedCameraImage)
            }
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordView()
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountSheet(username: viewModel.username)
            }
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
        .colorScheme(.light)
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
                avatarCard
                accountCard
                personalCard
                aboutCard
                appearanceCard
                feedCacheCard
                saveCard
                legalCard
                logoutCard
                deleteAccountCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var avatarCard: some View {
        VStack(spacing: 14) {
            ZStack {
                avatarCircle
                if viewModel.isUploadingAvatar {
                    Circle()
                        .fill(Color.appPrimaryText.opacity(0.35))
                        .frame(width: 96, height: 96)
                    ProgressView()
                        .tint(Color.appAccent)
                }
            }
            Menu {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label("Photo library", systemImage: "photo.on.rectangle")
                }
                .disabled(viewModel.isUploadingAvatar)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCameraPicker = true
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                    .disabled(viewModel.isUploadingAvatar)
                }
            } label: {
                Text("Change photo")
                    .font(.appDisplay(size: 13))
                    .foregroundStyle(.white)
            }
            .disabled(viewModel.isUploadingAvatar)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var avatarCircle: some View {
        Group {
            if let url = resolvedAvatarURL(from: viewModel.avatarUrl) {
                CachedAsyncImage(
                    url: url,
                    logContext: "avatar",
                    failurePlaceholder: {
                        AnyView(
                            ZStack {
                                Circle()
                                    .fill(Color.appPrimaryText.opacity(0.08))
                                avatarPlaceholderSymbol
                            }
                            .frame(width: 96, height: 96)
                        )
                    },
                    placeholder: {
                        AnyView(
                            ZStack {
                                Circle()
                                    .fill(Color.appPrimaryText.opacity(0.08))
                                ProgressView()
                                    .tint(Color.appAccent)
                            }
                            .frame(width: 96, height: 96)
                        )
                    }
                )
                .id(url.absoluteString)
                .frame(width: 96, height: 96)
                .clipShape(Circle())
            } else {
                avatarPlaceholderSymbol
                    .frame(width: 96, height: 96)
            }
        }
    }

    private var avatarPlaceholderSymbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 72))
            .foregroundStyle(Color.white)
            .accessibilityHidden(true)
    }

    private func resolvedAvatarURL(from string: String?) -> URL? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            settingsAvatarLog.debug("No avatar URL from profile (nil or empty).")
            return nil
        }
        let normalized = raw.normalizedAsHTTPURLString
        if let u = URL(string: normalized), u.scheme == "http" || u.scheme == "https" {
            settingsAvatarLog.debug("Resolved avatar URL host=\(u.host ?? "nil", privacy: .public)")
            return u
        }
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.insert(charactersIn: ":?&=%#")
        if let encoded = normalized.addingPercentEncoding(withAllowedCharacters: allowed),
           let u = URL(string: encoded), u.scheme == "http" || u.scheme == "https" {
            settingsAvatarLog.debug("Avatar URL required percent-encoding before parse.")
            return u
        }
        settingsAvatarLog.error("Avatar URL is not valid HTTP(S): \(raw, privacy: .public)")
        return nil
    }

    private func handlePhotoLibrarySelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = UIImage(data: data) else {
                await MainActor.run {
                    viewModel.errorMessage = "Could not load the photo."
                }
                await MainActor.run { photoPickerItem = nil }
                return
            }
            await viewModel.uploadAvatarFromUIImage(image)
        } catch {
            await MainActor.run {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        await MainActor.run { photoPickerItem = nil }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            VStack(alignment: .leading, spacing: 12) {
                emailRow
                Divider().opacity(0.35)
                settingsLabeledRow(title: "Username", value: viewModel.username)
                Divider().opacity(0.35)
                changePasswordRow
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private var emailRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Email")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            HStack(spacing: 8) {
                Text(viewModel.email)
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if authViewModel.needsEmailVerification {
                    Button {
                        Task { await authViewModel.resendVerificationEmail() }
                    } label: {
                        Text(verifyActionLabel)
                            .font(.appDisplay(size: 12))
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(authViewModel.resendState != .idle)
                } else if !viewModel.email.isEmpty {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Email verified")
                }
            }
        }
    }

    private var verifyActionLabel: String {
        switch authViewModel.resendState {
        case .idle: return "Not verified — resend"
        case .sending: return "Sending…"
        case .sent: return "Link sent"
        }
    }

    private var changePasswordRow: some View {
        Button {
            resignFirstResponder()
            showChangePassword = true
        } label: {
            HStack(alignment: .center) {
                Text("Change password")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appPrimaryText)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change password")
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

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Text("Choose how Clothedd looks. Changes apply instantly.")
                .font(.appDisplay(size: 15))
                .foregroundStyle(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                ForEach(ThemeStyle.allCases) { style in
                    PopArtSelectionRow(
                        label: style.displayName,
                        isSelected: ThemeStore.shared.style == style
                    ) {
                        resignFirstResponder()
                        withAnimation(.easeOut(duration: 0.25)) {
                            ThemeStore.shared.style = style
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
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

    private var legalCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Legal")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Link(destination: LegalLinks.privacyPolicy) {
                HStack {
                    Text("Privacy Policy")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appPrimaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .contentShape(Rectangle())
            }
            Divider()
            Link(destination: LegalLinks.termsOfService) {
                HStack {
                    Text("Terms of Service")
                        .font(.appDisplay(size: 17))
                        .foregroundStyle(Color.appPrimaryText)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .contentShape(Rectangle())
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .popArtCardContainer()
    }

    private var feedCacheCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Feed cache")
                .font(.appDisplay(size: 13))
                .foregroundStyle(Color.appSecondaryText)
            Text("Clears the offline feed snapshot and image cache for those items, then reloads the feed in the background with images validated and preloaded.")
                .font(.appDisplay(size: 15))
                .foregroundStyle(Color.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                resignFirstResponder()
                feedViewModel.clearPersistedFeedCache()
            } label: {
                Text("Clear feed cache")
                    .font(.appDisplay(size: 17))
                    .foregroundStyle(Color.appAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
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

    private var deleteAccountCard: some View {
        Button {
            resignFirstResponder()
            showDeleteAccount = true
        } label: {
            Text("Delete Account")
                .font(.appDisplay(size: 15))
                .foregroundStyle(.red.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Permanently deletes your account and data")
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
