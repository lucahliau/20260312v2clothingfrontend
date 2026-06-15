import Foundation
import MetricKit

/// Field crash visibility: subscribes to MetricKit, which delivers crash and
/// hang diagnostics on the launch *after* the incident. Payloads are written
/// to disk first (MetricKit only delivers each one once), then uploaded
/// best-effort to `POST /diagnostics/crash`; failures retry on later
/// launches/foregrounds via `uploadPending()`.
final class CrashReportService: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReportService()

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("CrashReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    /// Diagnostics (crashes, hangs) — called by MetricKit on a background queue.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let isCrash = !(payload.crashDiagnostics?.isEmpty ?? true)
            let name = "\(isCrash ? "crash" : "hang")-\(UUID().uuidString).json"
            try? payload.jsonRepresentation().write(to: Self.directory.appendingPathComponent(name))
        }
        Task { await Self.uploadPending() }
    }

    /// Uploads stored diagnostics; safe to call on every launch/foreground.
    static func uploadPending() async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil),
              !files.isEmpty else { return }
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = String(data: data.prefix(290_000), encoding: .utf8) else {
                try? fm.removeItem(at: file)
                continue
            }
            let kind = file.lastPathComponent.hasPrefix("hang") ? "hang" : "crash"
            do {
                try await NetworkManager.shared.requestVoid(
                    "/diagnostics/crash",
                    method: "POST",
                    body: CrashReportRequest(
                        payloadJson: json,
                        kind: kind,
                        appVersion: appVersion,
                        osVersion: osVersion
                    )
                )
                try? fm.removeItem(at: file)
            } catch {
                // Offline or logged out: keep the file and stop — the whole
                // batch would fail the same way. Retries next launch.
                break
            }
        }
    }
}

struct CrashReportRequest: Codable, Sendable {
    let payloadJson: String
    let kind: String
    let appVersion: String?
    let osVersion: String?
}
