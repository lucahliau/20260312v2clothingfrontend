import SwiftUI

/// Reasons a user can be reported for. Raw values match the backend's
/// accepted `reason` enum (POST /social/report/:userId).
enum ReportReason: String, CaseIterable {
    case harassment
    case spam
    case inappropriateContent = "inappropriate_content"
    case impersonation
    case scam
    case other

    var label: String {
        switch self {
        case .harassment: return "Harassment or bullying"
        case .spam: return "Spam"
        case .inappropriateContent: return "Inappropriate content"
        case .impersonation: return "Impersonation"
        case .scam: return "Scam or fraud"
        case .other: return "Something else"
        }
    }
}

/// Ellipsis toolbar menu offering Report / Block for another user.
/// Required for App Store guideline 1.2: apps with messaging must let users
/// flag abuse and block offenders from within the app.
struct UserModerationMenu: View {
    let userId: String
    let username: String
    /// Called after a successful block so the host view can refresh or dismiss.
    var onBlocked: (() -> Void)? = nil

    @State private var showReportDialog = false
    @State private var showBlockConfirm = false
    @State private var resultMessage: String?
    @State private var inFlight = false

    var body: some View {
        Menu {
            Button {
                showReportDialog = true
            } label: {
                Label("Report @\(username)", systemImage: "flag")
            }
            Button(role: .destructive) {
                showBlockConfirm = true
            } label: {
                Label("Block @\(username)", systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Color.appOnHalftonePrimary)
        }
        .disabled(inFlight)
        .confirmationDialog(
            "Report @\(username)",
            isPresented: $showReportDialog,
            titleVisibility: .visible
        ) {
            ForEach(ReportReason.allCases, id: \.rawValue) { reason in
                Button(reason.label) {
                    Task { await report(reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Reports are reviewed and can lead to content removal or account suspension.")
        }
        .confirmationDialog(
            "Block @\(username)?",
            isPresented: $showBlockConfirm,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) {
                Task { await block() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to message you or interact with you, and pending requests between you are removed.")
        }
        .alert(
            resultMessage ?? "",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private func report(_ reason: ReportReason) async {
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await SocialService.reportUser(userId: userId, reason: reason.rawValue)
            resultMessage = "Thanks — your report was sent and will be reviewed."
        } catch {
            resultMessage = "Couldn't send the report. Please try again."
        }
    }

    private func block() async {
        inFlight = true
        defer { inFlight = false }
        do {
            _ = try await SocialService.blockUser(userId: userId)
            resultMessage = "@\(username) has been blocked."
            onBlocked?()
        } catch {
            resultMessage = "Couldn't block this user. Please try again."
        }
    }
}
