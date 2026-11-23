import SwiftUI

/// Compact strip shown while `ServerReachability` says the Clothedd server is
/// not answering. Renders nothing when the server is reachable, so screens can
/// drop it into a `VStack` unconditionally:
///
/// ```swift
/// ServerUnreachableBanner { await viewModel.reload() }
/// ```
///
/// Retry probes `GET /health`; `onRecovered` runs when the server answers again
/// (whether through Retry or the automatic background probe).
struct ServerUnreachableBanner: View {
    /// Extra line appended to the message (e.g. "Swipes will sync later").
    var detail: String? = nil
    /// Called once each time the server becomes reachable again.
    var onRecovered: (() async -> Void)? = nil

    private var reachability: ServerReachability { .shared }

    var body: some View {
        Group {
            if !reachability.isReachable {
                strip
            }
        }
        .animation(.easeOut(duration: 0.22), value: reachability.isReachable)
        .onChange(of: reachability.recoveryCount) { _, _ in
            guard let onRecovered else { return }
            Task { await onRecovered() }
        }
    }

    private var strip: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(NetworkError.serverUnreachableMessage)
                    .font(.appDisplay(size: 12))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(.appDisplay(size: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await reachability.probe() }
            } label: {
                Group {
                    if reachability.isProbing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.appPrimaryText)
                    } else {
                        Text("Retry")
                            .font(.appDisplay(size: 12))
                            .fontWeight(.semibold)
                    }
                }
                .frame(minWidth: 44)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().stroke(Color.black, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(reachability.isProbing)
            .accessibilityLabel("Retry connecting to the server")
        }
        .foregroundStyle(Color.appPrimaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color(red: 1.0, green: 0.85, blue: 0.2))
        .overlay(
            Rectangle()
                .fill(Color.black)
                .frame(height: 2)
                .frame(maxHeight: .infinity, alignment: .bottom)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}
