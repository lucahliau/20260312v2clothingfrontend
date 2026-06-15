import Foundation

/// Public legal pages, served by the backend (see backend src/routes/legal.ts).
/// The same URLs go into App Store Connect as the privacy policy / terms links.
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://20260311-clothes-backend-production.up.railway.app/privacy")!
    static let termsOfService = URL(string: "https://20260311-clothes-backend-production.up.railway.app/terms")!
}
