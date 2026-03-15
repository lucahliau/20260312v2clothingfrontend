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

    static let genderOptions = ["Male", "Female", "Non-binary", "Prefer not to say"]

    private static let dobFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func loadProfile() async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await UserService.fetchCurrentUser()
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
        do {
            let user = try await UserService.updateProfile(update)
            firstName = user.firstName ?? ""
            lastName = user.lastName ?? ""
            bio = user.bio ?? ""
            gender = user.gender ?? ""
            location = user.location ?? ""
            if let dob = user.dateOfBirth {
                dateOfBirth = Self.dobFormatter.date(from: dob)
            }
            showSaveConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
