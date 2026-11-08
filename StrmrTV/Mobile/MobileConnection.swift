#if os(iOS)
import Foundation
import UIKit

/// Keeps the phone connected, as the Expo app's `BackendSettingsContext` does: re-selects the
/// route when the network changes (debounced 0.5 s), on return to the foreground and every
/// 30 s while a home network could take over from the tunnel; notices a server that stopped
/// answering (a request's transport failure, confirmed by `/health`); and retries with
/// backoff until it answers again. A confirmed device outage pauses retrying until the
/// network returns. `MobileRootView` shows the state: an offline screen before sign-in
/// completes, a banner after.
@MainActor
final class MobileConnection: ObservableObject {
    static let shared = MobileConnection()

    enum Status: Equatable {
        case online
        /// No network on the device.
        case offline
        /// The server didn't answer; `nextRetry` is when the next attempt starts (nil: now).
        case reconnecting(attempt: Int, nextRetry: Date?)
    }

    @Published private(set) var status: Status = .online
    /// Set briefly after a recovery, for the banner's "Back online".
    @Published private(set) var recoveredAt: Date?
    /// Downloads presented over the app while the server is out of reach.
    @Published var showsOfflineDownloads = false

    private let session = AppSession.shared
    private let monitor = MobileNetworkMonitor.shared
    private let selector = MobileConnectionSelector.shared
    private var retryTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var checkTask: Task<Bool, Never>?
    private var periodic: Timer?
    private var backgroundedAt: Date?
    private var started = false

    /// Seconds before each retry: quick at first, then every 30 s.
    static let backoff: [TimeInterval] = [2, 4, 8, 15, 30]

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.onChange = { [weak self] path in self?.networkChanged(path) }
        monitor.start()
        APIClient.shared.onTransportResult = { [weak self] error in self?.transportResult(error) }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.backgroundedAt = Date() }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.foregrounded() }
        }
        periodic = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.periodicCheck() }
        }
        if monitor.isDeviceOffline { status = .offline }
        #if DEBUG
        if let from = DebugNetworkFault.from {
            Task {
                try? await Task.sleep(for: .seconds(max(0, from.timeIntervalSinceNow) + 0.1))
                monitor.refresh()
                await verify(reason: "network failure")
            }
        }
        #endif
    }

    /// The session reached a phase: offline at the startup error retries by itself; signed in,
    /// the network settings are read again.
    func phaseChanged(_ phase: AppSession.Phase) {
        switch phase {
        case .unavailable:
            MobileReconnectJournal.record("startup-unavailable")
            if monitor.isDeviceOffline { status = .offline } else { scheduleRetry(attempt: 0) }
        case .ready:
            Task { await selector.refreshSettings() }
        default:
            break
        }
    }

    #if DEBUG
    /// Connection settings' Debug switch: applies a simulated fault now.
    func simulate(_ mode: DebugNetworkFault.Mode) {
        DebugNetworkFault.set(mode)
        MobileReconnectJournal.record("debug-fault", ["mode": mode.rawValue])
        monitor.refresh()
        if mode == .unreachable { Task { await verify(reason: "network failure") } }
    }
    #endif

    /// Try Again, the banner's Retry, or Reconnect in settings: an attempt now.
    func retryNow() {
        guard !monitor.isDeviceOffline else { status = .offline; return }
        let attempt: Int
        if case let .reconnecting(n, _) = status { attempt = n } else { attempt = 0 }
        retryTask?.cancel()
        retryTask = Task { await attemptReconnect(attempt: attempt) }
    }

    /// Check Connection in settings: one health check now; a failure starts the retry loop.
    func checkNow() async -> Bool {
        let ok = await check()
        if ok {
            if status != .online { recovered() }
        } else if status == .online, session.phase == .ready || isUnavailable {
            scheduleRetry(attempt: 0)
        }
        return ok
    }

    // MARK: Events

    private func networkChanged(_ path: MobileNetworkMonitor.Path) {
        if monitor.isDeviceOffline || !path.satisfied {
            // Wait for the two-second confirmation before calling it an outage.
            changeTask?.cancel()
            changeTask = Task {
                try? await Task.sleep(for: .seconds(2.1))
                guard !Task.isCancelled, monitor.isDeviceOffline else { return }
                goOffline()
            }
            return
        }
        changeTask?.cancel()
        changeTask = Task {
            try? await Task.sleep(for: .milliseconds(500))  // coalesce the handover burst
            guard !Task.isCancelled, UIApplication.shared.applicationState != .background else { return }
            MobileReconnectJournal.record("network-change", ["interface": path.interface.rawValue])
            await selector.select(reason: "network change")
            await verify(reason: "network change")
        }
    }

    private func foregrounded() {
        let away = backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0
        backgroundedAt = nil
        guard away >= 1 else { return }
        MobileReconnectJournal.record("app-foreground", ["offline": monitor.isDeviceOffline ? "true" : "false"])
        if monitor.isDeviceOffline { goOffline(); return }
        Task {
            await selector.select(reason: "app active")
            await verify(reason: "app active")
            if session.phase == .ready { await selector.refreshSettings() }
        }
    }

    private func periodicCheck() {
        guard UIApplication.shared.applicationState == .active, session.phase == .ready,
              status == .online, selector.automaticHome != nil || session.isHomeDirect
        else { return }
        let before = session.serverURL
        Task {
            await selector.select(reason: "periodic")
            if session.serverURL != before { await verify(reason: "periodic route change") }
        }
    }

    /// A request's outcome. Failures while signed in are checked against `/health` before the
    /// banner shows, so one dropped request doesn't count as an outage.
    private func transportResult(_ error: URLError?) {
        guard let error else { return }
        guard ![.cancelled, .userCancelledAuthentication].contains(error.code), session.phase == .ready, status == .online else { return }
        if [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff].contains(error.code), monitor.isDeviceOffline {
            goOffline()
            return
        }
        Task { await verify(reason: "network failure") }
    }

    // MARK: Checks

    /// One health check (shared by concurrent callers); starts the retry loop when it fails.
    private func verify(reason: String) async {
        guard session.phase == .ready || isUnavailable else { return }
        if isUnavailable {
            if case .reconnecting = status { return }
            scheduleRetry(attempt: 0)
            return
        }
        let ok = await check()
        if ok {
            if status != .online { recovered() }
        } else if case .reconnecting = status {
            return
        } else {
            // The retry re-selects the route first (on the home network, back to the tunnel).
            MobileReconnectJournal.record("server-unreachable", ["reason": reason])
            scheduleRetry(attempt: 0)
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = session.phase { return true }
        return false
    }

    private func check() async -> Bool {
        if let checkTask { return await checkTask.value }
        let task = Task<Bool, Never> {
            if monitor.isDeviceOffline { return false }
            if session.isRemote {
                guard (try? await session.reconnectRemoteOrThrow()) != nil else { return false }
            }
            return (try? await APIClient.shared.sendRaw("GET", "/health", authorized: false, timeout: 6)) != nil
        }
        checkTask = task
        let ok = await task.value
        checkTask = nil
        return ok
    }

    private func scheduleRetry(attempt: Int) {
        let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
        status = .reconnecting(attempt: attempt, nextRetry: Date().addingTimeInterval(delay))
        retryTask?.cancel()
        retryTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await attemptReconnect(attempt: attempt)
        }
    }

    private func attemptReconnect(attempt: Int) async {
        guard !monitor.isDeviceOffline else { goOffline(); return }
        status = .reconnecting(attempt: attempt, nextRetry: nil)
        MobileReconnectJournal.record("retry", ["attempt": "\(attempt + 1)"])
        await selector.select(reason: "retry")
        guard !Task.isCancelled else { return }
        let ok = await check()
        guard !Task.isCancelled else { return }
        if ok, isUnavailable {
            await session.retryStartup()
            if isUnavailable { scheduleRetry(attempt: attempt + 1) } else { recovered() }
        } else if ok {
            recovered()
        } else {
            scheduleRetry(attempt: attempt + 1)
        }
    }

    private func goOffline() {
        retryTask?.cancel()
        retryTask = nil
        guard status != .offline else { return }
        status = .offline
        MobileReconnectJournal.record("offline")
    }

    private func recovered() {
        retryTask?.cancel()
        retryTask = nil
        let wasDown = status != .online
        status = .online
        guard wasDown else { return }
        MobileReconnectJournal.record("reconnected")
        recoveredAt = Date()
        // Rows that failed while the server was away fill in again.
        if session.phase == .ready { NotificationCenter.default.post(name: .continueWatchingChanged, object: nil) }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if let at = recoveredAt, Date().timeIntervalSince(at) >= 3 { recoveredAt = nil }
        }
    }
}
#endif
