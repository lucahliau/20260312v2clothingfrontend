import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = SettingsViewModel()
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading profile...")
                } else {
                    profileForm
                }
            }
            .navigationTitle("Settings")
            .task { await viewModel.loadProfile() }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Saved", isPresented: $viewModel.showSaveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your profile has been updated.")
            }
            .confirmationDialog("Log Out", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
                Button("Log Out", role: .destructive) {
                    Task { await authViewModel.logout() }
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
        }
    }

    private var profileForm: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: viewModel.email)
                LabeledContent("Username", value: viewModel.username)
            }

            Section("Personal Info") {
                TextField("First Name", text: $viewModel.firstName)
                    .textContentType(.givenName)

                TextField("Last Name", text: $viewModel.lastName)
                    .textContentType(.familyName)

                DatePicker(
                    "Date of Birth",
                    selection: Binding(
                        get: { viewModel.dateOfBirth ?? Date() },
                        set: { viewModel.dateOfBirth = $0 }
                    ),
                    in: ...Date.now,
                    displayedComponents: .date
                )

                Picker("Gender", selection: $viewModel.gender) {
                    Text("Not set").tag("")
                    ForEach(SettingsViewModel.genderOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }

                TextField("Location", text: $viewModel.location)
                    .textContentType(.addressCity)
            }

            Section("About") {
                TextField("Bio", text: $viewModel.bio, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    Task { await viewModel.saveProfile() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Save Changes")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isSaving)
            }

            Section {
                Button("Log Out", role: .destructive) {
                    showLogoutConfirmation = true
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
