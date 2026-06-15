import Foundation
import Network
import Observation

/// App-wide reachability via NWPathMonitor. Views observe `isOnline` for
/// offline banners; the offline→online transition replays the pending swipe
/// queue automatically.
@Observable
@MainActor
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    private(set) var isOnline = true

    /// True on cellular / personal hotspot (`isExpensive`) or Low Data Mode
    /// (`isConstrained`). Heavy background image prefetch is skipped when set,
    /// so we never burn the user's mobile data warming tabs they may not open.
    private(set) var isConstrained = false

    /// Gate for opportunistic, non-essential image prefetching: online and on
    /// an unconstrained (e.g. Wi-Fi) link. Cheap data loads ignore this.
    var allowsHeavyPrefetch: Bool { isOnline && !isConstrained }

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let constrained = path.isExpensive || path.isConstrained
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConstrained = constrained
                guard self.isOnline != online else { return }
                self.isOnline = online
                if online {
                    await PendingSwipeQueue.shared.flush()
                    await AnalyticsQueue.shared.flush()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity-monitor"))
    }
}
