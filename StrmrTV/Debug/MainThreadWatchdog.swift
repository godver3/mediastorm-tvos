import Foundation
import UIKit

/// Logs when the main thread stops answering, from a queue that keeps running while it is stuck.
/// tvOS kills an app whose main thread hangs too long without raising a signal `CrashReporter`
/// could catch, so these lines are the only trace such an exit leaves in a submitted log. Only one
/// ping is ever outstanding, and it is dropped while the app is inactive, when a suspended main
/// thread is expected.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private static let threshold: TimeInterval = 2
    private static let repeatEvery: TimeInterval = 5
    private let log = AppLog(category: "watchdog")
    private let queue = DispatchQueue(label: "com.strmr.app.nx.watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    // Confined to `queue`.
    private var active = true
    private var generation: UInt64 = 0
    private var pingSentAt: TimeInterval?
    private var lastReportAt: TimeInterval?

    /// Not main-actor isolated, so the closures below don't inherit an isolation that the
    /// runtime would check (and trap on) when they run on `queue`. Call it once, at launch.
    nonisolated func start() {
        guard timer == nil else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: nil) { [weak self] _ in self?.setActive(true) })
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
                                            object: nil, queue: nil) { [weak self] _ in self?.setActive(false) })
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    private func setActive(_ value: Bool) {
        queue.async { [self] in
            active = value
            generation &+= 1
            pingSentAt = nil
            lastReportAt = nil
        }
    }

    private func tick() {
        guard active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let sentAt = pingSentAt else {
            pingSentAt = now
            let ping = generation
            DispatchQueue.main.async { [self] in
                let answeredAt = ProcessInfo.processInfo.systemUptime
                queue.async { self.answered(ping, at: answeredAt) }
            }
            return
        }
        let stalled = now - sentAt
        guard stalled >= Self.threshold else { return }
        if let lastReportAt, now - lastReportAt < Self.repeatEvery { return }
        lastReportAt = now
        log.error("main thread unresponsive for \(Int(stalled * 1000))ms")
    }

    private func answered(_ ping: UInt64, at answeredAt: TimeInterval) {
        guard ping == generation, let sentAt = pingSentAt else { return }
        let stalled = answeredAt - sentAt
        if stalled >= Self.threshold { log.error("main thread answered after \(Int(stalled * 1000))ms") }
        pingSentAt = nil
        lastReportAt = nil
    }
}
