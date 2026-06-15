import SwiftUI

/// First-run calibration flow, shown as a full-screen cover until the server
/// reports `onboardingCompleted`. Three quick questions — gender, styles,
/// favorite brands — saved via `POST /users/me/onboarding`, which also seeds
/// the Feed's default gender filter and the recommender's cold start.
struct OnboardingView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(SettingsViewModel.self) private var settingsViewModel

    private enum Step: Int, CaseIterable {
        case welcome, gender, styles, brands
    }

    @State private var step: Step = .welcome
    @State private var selectedGender: String?
    @State private var selectedStyles: Set<ProductType> = []
    @State private var selectedBrands: Set<String> = []
    @State private var brandOptions: [BrandInfo] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let styleChoices: [ProductType] = [.tops, .bottoms, .jackets, .bags, .accessories]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                Group {
                    switch step {
                    case .welcome: welcomeStep
                    case .gender: genderStep
                    case .styles: stylesStep
                    case .brands: brandsStep
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 20)
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PopArtHalftoneBackground() }
        .interactiveDismissDisabled()
        .task { await loadBrandOptions() }
        .overlay {
            if let message = errorMessage {
                PopArtMessageAlert(title: "Couldn't save", message: message) {
                    errorMessage = nil
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.2), value: errorMessage)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Color.appNeonPink : Color.white.opacity(0.4))
                        .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
                        .frame(width: s == step ? 26 : 12, height: 8)
                }
            }
            Spacer()
            if !isSaving {
                Button("Skip") {
                    Task { await skip() }
                }
                .font(.appDisplay(size: 14))
                .foregroundStyle(Color.white)
                .shadow(color: .black, radius: 0, x: 1.2, y: 1.2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
    }

    private var footer: some View {
        Button {
            advance()
        } label: {
            HStack(spacing: 10) {
                if isSaving {
                    ProgressView().tint(.white)
                }
                Text(footerTitle)
                    .font(.appDisplay(size: 17))
                Image(systemName: step == .brands ? "checkmark" : "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canAdvance ? Color.appNeonPink : Color.gray.opacity(0.6))
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black, lineWidth: 2.5))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
                    .offset(x: 3, y: 3)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance || isSaving)
        .padding(.horizontal, 26)
        .padding(.bottom, 18)
    }

    private var footerTitle: String {
        switch step {
        case .welcome: return "Let's go"
        case .gender, .styles: return "Continue"
        case .brands: return "Start swiping"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .styles: return !selectedStyles.isEmpty
        default: return true
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Text("WELCOME TO\nCLOTHEDD")
                .font(.appDisplay(size: 38))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white)
                .shadow(color: .black, radius: 0, x: 3, y: 3)
                .padding(.top, 30)
            PopArtTag(rotation: -2) {
                Text("Answer three quick questions so your Feed starts with stuff you'll actually love.")
                    .font(.appDisplay(size: 14))
                    .foregroundStyle(Color.appPrimaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var genderStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Who do you shop for?")
            stepSubtitle("Sets your default Feed filter — you can change it anytime.")
            VStack(spacing: 12) {
                genderRow("Menswear", value: "Male")
                genderRow("Womenswear", value: "Female")
                genderRow("Show me everything", value: nil)
            }
        }
    }

    private func genderRow(_ label: String, value: String?) -> some View {
        let isSelected = selectedGender == value
        return Button {
            selectedGender = value
        } label: {
            HStack {
                Text(label)
                    .font(.appDisplay(size: 16))
                    .foregroundStyle(isSelected ? Color.white : Color.appPrimaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.appNeonPink : Color.white)
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.black, lineWidth: 2.5))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                    .offset(x: 3, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private var stylesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("What are you into?")
            stepSubtitle("Pick at least one — your Feed leans into these first.")
            chipFlow(
                labels: Self.styleChoices.map(\.displayName),
                isSelected: { label in
                    selectedStyles.contains { $0.displayName == label }
                },
                toggle: { label in
                    guard let type = Self.styleChoices.first(where: { $0.displayName == label }) else { return }
                    if selectedStyles.contains(type) {
                        selectedStyles.remove(type)
                    } else {
                        selectedStyles.insert(type)
                    }
                }
            )
        }
    }

    private var brandsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Any favorite brands?")
            stepSubtitle("Optional — tap the ones you rate.")
            if brandOptions.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else {
                chipFlow(
                    labels: brandOptions.map(\.brand),
                    isSelected: { selectedBrands.contains($0) },
                    toggle: { brand in
                        if selectedBrands.contains(brand) {
                            selectedBrands.remove(brand)
                        } else {
                            selectedBrands.insert(brand)
                        }
                    },
                    displayLabel: { $0.displayNormalizedTitle }
                )
            }
        }
    }

    // MARK: - Shared pieces

    private func stepTitle(_ text: String) -> some View {
        Text(text)
            .font(.appDisplay(size: 27))
            .foregroundStyle(Color.white)
            .shadow(color: .black, radius: 0, x: 2.5, y: 2.5)
    }

    private func stepSubtitle(_ text: String) -> some View {
        Text(text)
            .font(.appDisplay(size: 13))
            .foregroundStyle(Color.white.opacity(0.92))
            .shadow(color: .black, radius: 0, x: 1.2, y: 1.2)
    }

    /// Wrapping rows of selectable pop-art capsules.
    private func chipFlow(
        labels: [String],
        isSelected: @escaping (String) -> Bool,
        toggle: @escaping (String) -> Void,
        displayLabel: @escaping (String) -> String = { $0 }
    ) -> some View {
        FlowLayout(spacing: 10) {
            ForEach(labels, id: \.self) { label in
                let selected = isSelected(label)
                Button {
                    toggle(label)
                } label: {
                    Text(displayLabel(label))
                        .font(.appDisplay(size: 14))
                        .foregroundStyle(selected ? Color.white : Color.appPrimaryText)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(selected ? Color.appNeonPink : Color.white))
                        .overlay(Capsule().stroke(Color.black, lineWidth: 2.5))
                        .background(Capsule().fill(Color.black).offset(x: 2.5, y: 2.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func advance() {
        switch step {
        case .welcome: step = .gender
        case .gender: step = .styles
        case .styles: step = .brands
        case .brands: Task { await save() }
        }
    }

    private func loadBrandOptions() async {
        guard brandOptions.isEmpty else { return }
        if let brands = try? await BrandService.fetchExploreBrands(limit: 18) {
            brandOptions = brands
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let request = OnboardingRequest(
                stylePreferences: selectedStyles.map(\.rawValue).sorted(),
                favoriteBrands: Array(selectedBrands).sorted(),
                preferredSizes: [:],
                gender: selectedGender
            )
            let user = try await UserService.saveOnboarding(request)
            settingsViewModel.applyOnboardedUser(user)
            authViewModel.completeOnboarding()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Mark onboarding done without answers. A network failure still closes
    /// the flow locally — the user just gets asked again next launch.
    private func skip() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        var update = UserUpdateRequest()
        update.onboardingCompleted = true
        if let user = try? await UserService.updateProfile(update) {
            settingsViewModel.applyOnboardedUser(user)
        }
        authViewModel.completeOnboarding()
    }
}

/// Minimal wrapping flow layout for the selectable chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
