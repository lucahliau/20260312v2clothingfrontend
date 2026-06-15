import Foundation
import Observation
import UIKit

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
    var avatarUrl: String?

    var isLoading = false
    var isSaving = false
    var isUploadingAvatar = false
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

    /// Push a fresh `User` (e.g. the onboarding save response) into the profile
    /// state without another network round trip. Marks the profile as loaded so
    /// gender-dependent consumers (Feed default filter) react immediately.
    func applyOnboardedUser(_ user: User) {
        apply(user: user)
        lastProfileLoadAt = Date()
    }

    private func apply(user: User) {
        firstName = user.firstName ?? ""
        lastName = user.lastName ?? ""
        bio = user.bio ?? ""
        gender = user.gender ?? ""
        location = user.location ?? ""
        email = user.email
        username = user.username
        avatarUrl = user.avatarUrl
        if let dob = user.dateOfBirth {
            dateOfBirth = Self.dobFormatter.date(from: dob)
        }
    }

    func uploadAvatarFromUIImage(_ image: UIImage) async {
        guard let data = AvatarImageProcessor.jpegDataForUpload(from: image) else {
            errorMessage = "Could not process the image."
            return
        }
        await uploadAvatar(imageData: data, fileExt: "jpg", contentType: "image/jpeg")
    }

    private func uploadAvatar(imageData: Data, fileExt: String, contentType: String) async {
        isUploadingAvatar = true
        errorMessage = nil
        defer { isUploadingAvatar = false }
        do {
            let slot = try await UserService.getAvatarUploadUrl(fileExt: fileExt)
            try await NetworkManager.shared.putBytes(imageData, to: slot.signedUrl, contentType: contentType)
            let user = try await UserService.updateAvatarUrl(slot.publicUrl)
            apply(user: user)
            lastProfileLoadAt = Date()
        } catch {
            errorMessage = error.localizedDescription
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
