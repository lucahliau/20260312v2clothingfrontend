import Foundation
import Observation

@Observable
final class SettingsViewModel {
    var firstName: String = ""
    var lastName: String = ""
    var bio: String = ""
    var gender: String = ""
    var dateOfBirth: Date? = nil
    var location: String = ""
    var email: String = ""
    var username: String = ""

    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    var showSaveConfirmation = false

    /// `nil` until first successful profile fetch; used to show initial loading UI only once.
    private(set) var lastProfileLoadAt: Date?

    private let staleDuration: TimeInterval = 120

    static let genderOptions = ["Male", "Female", "Non-binary", "Prefer not to say"]

    private static let dobFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func loadProfileIfNeeded() async {
        if lastProfileLoadAt == nil {
            await loadProfileInitial()
        } else {
            await refreshProfileIfStale()
        }
    }

    private func loadProfileInitial() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let user = try await UserService.fetchCurrentUser()
            apply(user: user)
            lastProfileLoadAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshProfileIfStale() async {
        guard let last = lastProfileLoadAt else {
            await refreshProfileSilently()
            return
        }
        if Date().timeIntervalSince(last) < staleDuration { return }
        await refreshProfileSilently()
    }

    private func refreshProfileSilently() async {
        do {
            let user = try await UserService.fetchCurrentUser()
            apply(user: user)
            lastProfileLoadAt = Date()
        } catch {
            // Keep existing fields
        }
    }

    private func apply(user: User) {
        firstName = user.firstName ?? ""
        lastName = user.lastName ?? ""
        bio = user.bio ?? ""
        gender = user.gender ?? ""
        location = user.location ?? ""
        email = user.email
        username = user.username
        if let dob = user.dateOfBirth {
            dateOfBirth = Self.dobFormatter.date(from: dob)
        }
    }

    func saveProfile() async {
        isSaving = true
        errorMessage = nil
        let dobString: String? = dateOfBirth.map { Self.dobFormatter.string(from: $0) }
        let update = UserUpdateRequest(
            firstName: firstName.isEmpty ? nil : firstName,
            lastName: lastName.isEmpty ? nil : lastName,
            bio: bio.isEmpty ? nil : bio,
            gender: gender.isEmpty ? nil : gender,
            dateOfBirth: dobString,
            location: location.isEmpty ? nil : location
        )
        defer { isSaving = false }
        do {
            let user = try await UserService.updateProfile(update)
            apply(user: user)
            lastProfileLoadAt = Date()
            showSaveConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
