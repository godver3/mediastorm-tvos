import Combine
import Foundation
import UIKit

private let log = AppLog(category: "adaptive")

/// Adaptive playback's client speed, a port of the Expo app's
/// `refreshAdaptiveThroughputEstimate` and its triggers in `BackendSettingsContext`:
///
/// - While the profile's (else the server's) `filtering.adaptivePlaybackEnabled` is on, an idle
///   speed test runs 15 s after a profile is in use and 15 s after each return to the foreground,
///   unless the route already has a fresh estimate. Going to the background cancels a pending
///   one, and it never starts while a stream resolves or a player is up.
/// - Settings' Test Connection Speed saves a `manual` estimate (when adaptive playback is on).
/// - Searches and prequeues carry the route's fresh estimate as `X-Adaptive-Throughput-*`.
///
/// Logs as `[adaptive]`.
@MainActor
final class AdaptiveThroughput: ObservableObject {
    static let shared = AdaptiveThroughput()

    /// This route's stored estimate, fresh or not, for Settings.
    @Published private(set) var estimate: AdaptiveThroughputEstimate?
    /// Settings' last manual result (shown whether or not adaptive playback saved it).
    @Published private(set) var manualResult: (sample: SpeedTestSample, at: Date)?
    @Published private(set) var manualRunning = false
    @Published private(set) var manualError: String?

    private let api = APIClient.shared
    private let store = AdaptiveThroughputStore()
    private var idleTimer: Task<Void, Never>?
    private var idleRunning = false
    private var profileWatch: AnyCancellable?

    /// Starts following the session: a profile coming into use (Expo's "settings loaded") and each
    /// return to the foreground schedule the idle test; the background cancels it.
    func start() {
        guard profileWatch == nil else { return }
        profileWatch = AppSession.shared.$profile
            .map { $0?.id }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in
                guard let self, id != nil else { return }
                self.reload()
                self.scheduleIdle(trigger: "settings-loaded-idle")
            }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AppSession.shared.phase == .ready else { return }
                self?.scheduleIdle(trigger: "foreground-idle")
            }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelIdle() }
        }
    }

    /// Expo `getAdaptiveThroughputRouteKey`: remote access is one route whatever the proxy's port.
    var routeKey: String {
        api.remoteCredential != nil ? "transport:iroh" : AdaptiveThroughputStore.routeKey(api.baseURL.absoluteString)
    }

    /// Headers for a search or prequeue: the route's fresh estimate, else none.
    func requestHeaders() -> [String: String] {
        let key = routeKey
        let stored = store.stored(for: key)
        let fresh = stored.flatMap { AdaptiveThroughputStore.isFresh($0) ? $0 : nil }
        let age = stored.map { Int(Date().timeIntervalSince1970) - $0.measuredAt }
        log.info("client route estimate lookup route=\(key) found=\(stored != nil) valid=\(fresh != nil) "
                 + "ageS=\(age.map(String.init) ?? "-") mbps=\(stored.map { String($0.measuredMbps) } ?? "-") "
                 + "source=\(stored?.source.rawValue ?? "-")")
        return fresh?.headers ?? [:]
    }

    /// Re-reads the stored estimate for Settings.
    func reload() {
        estimate = store.stored(for: routeKey)
    }

    // MARK: Idle test

    /// Schedules the idle test (Expo `scheduleIdleThroughputRefresh`) when adaptive playback is on.
    func scheduleIdle(trigger: String) {
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            guard let self else { return }
            guard await self.api.adaptivePlaybackEnabled() else {
                log.info("idle throughput refresh not scheduled; adaptive playback is off trigger=\(trigger)")
                return
            }
            log.info("idle throughput refresh scheduled in 15s trigger=\(trigger)")
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            self.idleTimer = nil
            guard UIApplication.shared.applicationState == .active else { return }
            if PlaybackCoordinator.shared.isBusy {
                log.info("idle throughput refresh skipped; playback is active trigger=\(trigger)")
                return
            }
            await self.refresh(force: false, trigger: trigger)
        }
    }

    private func cancelIdle() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    /// Expo `refreshAdaptiveThroughputEstimate`: skipped while the route's estimate is fresh.
    func refresh(force: Bool, trigger: String) async {
        let key = routeKey
        if !force, store.fresh(for: key) != nil {
            log.info("idle throughput refresh skipped; route estimate is fresh route=\(key) trigger=\(trigger)")
            return
        }
        guard !idleRunning, !manualRunning else { return }
        idleRunning = true
        defer { idleRunning = false }
        let plan = ConnectionSpeedTest.idle
        log.info("throughput speed test started route=\(key) force=\(force) trigger=\(trigger) "
                 + "samples=\(plan.samples) streams=\(plan.parallelStreams) minMs=\(Int(plan.minElapsedMs))")
        do {
            let sample = try await api.runSpeedTest(plan)
            guard let saved = store.save(route: key, mbps: sample.speedMbps, source: .idle) else {
                log.error("throughput measurement rejected mbps=\(sample.speedMbps)")
                return
            }
            log.notice("throughput measurement accepted route=\(key) mbps=\(saved.measuredMbps) "
                       + "measuredAt=\(saved.measuredAt) " + Self.describe(sample))
            if routeKey == key { estimate = saved }
        } catch {
            log.error("throughput measurement failed: \(error.localizedDescription)")
        }
    }

    // MARK: Manual test

    /// Settings' Test Connection Speed: the full ladder, saved as `manual` while adaptive playback is on.
    func runManual() async {
        guard !manualRunning else { return }
        manualRunning = true
        manualError = nil
        defer { manualRunning = false }
        let key = routeKey
        do {
            let sample = try await api.runSpeedTest(ConnectionSpeedTest.manual)
            manualResult = (sample, Date())
            log.notice("manual connection speed test result route=\(key) " + Self.describe(sample))
            if await api.adaptivePlaybackEnabled(), let saved = store.save(route: key, mbps: sample.speedMbps, source: .manual) {
                log.notice("updated client-owned adaptive speed from manual test mbps=\(saved.measuredMbps) measuredAt=\(saved.measuredAt)")
            }
            reload()
        } catch {
            manualError = error.localizedDescription
            log.error("manual connection speed test failed: \(error.localizedDescription)")
        }
    }

    private static func describe(_ s: SpeedTestSample) -> String {
        "bytes=\(s.receivedBytes) speedMbps=\(String(format: "%.1f", s.speedMbps)) elapsedMs=\(Int(s.elapsedMs)) "
            + "setupMs=\(Int(s.setupMs)) transferMs=\(Int(s.transferMs)) streams=\(s.parallelStreams)"
    }
}
