import Foundation

/// Public legal pages, served by the backend (see backend src/routes/legal.ts).
/// The same URLs go into App Store Connect as the privacy policy / terms links.
enum LegalLinks {
    static let privacyPolicy = URL(string: "https://ls-macbook-air.taild99b83.ts.net:8445/privacy")!
    static let termsOfService = URL(string: "https://ls-macbook-air.taild99b83.ts.net:8445/terms")!
}
