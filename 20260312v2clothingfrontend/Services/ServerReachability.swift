import Foundation
import Observation

/// Whether the Clothedd server (reachable only over the owner's Tailscale
/// network) is answering. Unlike `ConnectivityMonitor` (NWPathMonitor, which
/// reports "online" on Wi-Fi with Tailscale off), this is driven by real
/// request outcomes in `NetworkManager` plus a `GET /health` probe.
///
/// Adopting it on a screen:
/// ```swift
/// ServerUnreachableBanner { await viewModel.reload() }   // hides itself when reachable
/// ```
/// or observe `ServerReachability.shared.isReachable` directly.
@Observable
@MainActor
final class ServerReachability {
    static let shared = ServerReachability()

    /// `false` once a request to the server failed at the transport level;
    /// back to `true` on the next request (or health probe) that gets any
    /// HTTP response. Optimistically `true` until proven otherwise.
    private(set) var isReachable = true
    /// A manual or automatic `/health` probe is in flight.
    private(set) var isProbing = false
    /// Bumped on every unreachable → reachable transition, so screens can
    /// `.task(id:)` / `.onChange` on it to reload what failed.
    private(set) var recoveryCount = 0

    @ObservationIgnored private var autoProbeTask: Task<Void, Never>?
    /// Seconds between automatic probes while unreachable.
    private static let autoProbeInterval: UInt64 = 10

    private init() {}

    // MARK: - Fed by NetworkManager

    func noteRequestSucceeded() {
        guard !isReachable else { return }
        isReachable = true
        recoveryCount += 1
        autoProbeTask?.cancel()
        autoProbeTask = nil
        // Same replay ConnectivityMonitor does on offline → online: swipes and
        // analytics queued while the server was away go out now.
        Task {
            await PendingSwipeQueue.shared.flush()
            await AnalyticsQueue.shared.flush()
        }
    }

    func noteRequestFailed() {
        if isReachable { isReachable = false }
        startAutoProbeIfNeeded()
    }

    // MARK: - Probing

    /// Hits `GET /health` once. Returns whether the server answered. The
    /// request itself updates `isReachable` through `NetworkManager`.
    @discardableResult
    func probe() async -> Bool {
        guard !isProbing else { return isReachable }
        isProbing = true
        defer { isProbing = false }
        do {
            _ = try await HealthService.checkHealth()
            return true
        } catch NetworkError.serverUnreachable {
            return false
        } catch {
            // Got an HTTP response of some kind (5xx, odd body): reachable.
            return isReachable
        }
    }

    /// While unreachable, quietly re-probe so banners clear by themselves when
    /// Tailscale comes back or the home server wakes.
    private func startAutoProbeIfNeeded() {
        guard autoProbeTask == nil else { return }
        autoProbeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.autoProbeInterval * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.isReachable { break }
                await self.probe()
            }
            self?.autoProbeTask = nil
        }
    }
}
