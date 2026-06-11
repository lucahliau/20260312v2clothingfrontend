import Foundation

/// Where the error happened — the same status can mean different things
/// (a 401 on login is a wrong password; a 401 elsewhere is a dead session).
enum AuthErrorContext {
    case login
    case register
    case changePassword
    case general
}

/// Turns transport/API errors into copy a person can act on. Raw
/// `localizedDescription` strings ("Server error 423: …") never reach the UI.
enum AuthErrorMapper {
    static func message(for error: Error, context: AuthErrorContext = .general) -> String {
        guard let net = error as? NetworkError else {
            return "Something went wrong. Try again."
        }
        switch net {
        case .unauthorized:
            switch context {
            case .login: return "Incorrect email/username or password."
            case .changePassword: return "Your current password is incorrect."
            case .register, .general: return "Your session expired. Please log in again."
            }
        case .serverError(let status, let message, let code):
            switch code {
            case "ACCOUNT_LOCKED":
                return "Too many attempts. Try again in 15 minutes."
            case "CONFLICT":
                return "That email or username is already taken."
            case "RATE_LIMITED":
                return "Slow down a little — try again in a minute."
            case "EMAIL_NOT_VERIFIED":
                return "Verify your email first — check your inbox for the link."
            case "VALIDATION_ERROR":
                return message ?? "Check your details and try again."
            default:
                if status >= 500 { return "Something went wrong on our side. Try again in a moment." }
                return message ?? "Something went wrong. Try again."
            }
        case .transient:
            return "Couldn't reach the server. Check your connection and try again."
        case .decodingError, .noData:
            return "Unexpected response from the server. Try again."
        case .invalidURL, .unknown:
            return "Something went wrong. Try again."
        }
    }
}
