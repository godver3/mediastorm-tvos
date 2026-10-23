import UIKit

// MARK: Idle-connection recovery
//
// A long pause lets the source's HTTP connection go idle and die; the resume read then
// never completes. Reconnecting in place proved unreliable, so the player saves progress
// and returns to the details page, where Resume is offered:
// - Device sleep / app switch backgrounds the app: leave on return to the foreground.
// - The screensaver over a paused player sends no lifecycle event: after a resume from a
//   long pause, leave only if the resume makes no progress or the engine errors / hits a
//   false end-of-file. A healthy resume progresses within a second and disarms the watch,
//   so a long pause on a live connection is never cut short.

extension PlayerViewController {
    func observeAppLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appDidEnterBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appWillEnterForeground() }
            },
        ]
    }

    private func appDidEnterBackground() {
        guard !didFinish else { return }
        log.notice("app backgrounded at \(self.lastKnownPosition)s; saving progress")
        isInBackground = true
        wasBackgrounded = true
        disarmResumeWatch()
        reportProgress(ended: false, paused: true)
    }

    private func appWillEnterForeground() {
        isInBackground = false
        guard wasBackgrounded, !didFinish else { return }
        exitToDetails(reason: "returned from background")
    }

    func armResumeWatch() {
        disarmResumeWatch()
        let position = lastKnownPosition
        log.notice("resume after long pause at \(position)s; watching for progress")
        let timer = Timer.scheduledTimer(withTimeInterval: Self.resumeProgressWindow, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.resumeWatch != nil else { return }
                self.exitToDetails(reason: "no progress \(Int(Self.resumeProgressWindow))s after resume")
            }
        }
        resumeWatch = (position, timer)
    }

    func disarmResumeWatch() {
        resumeWatch?.timer.invalidate()
        resumeWatch = nil
    }

    /// Records healthy progress and disarms the resume watch on the first real advance.
    func noteProgress(_ time: Double) {
        guard !isInBackground, time > 0, engine.state == .playing || engine.state == .paused else { return }
        lastKnownPosition = time
        if engine.duration > 0 { lastKnownDuration = engine.duration }
        if let watch = resumeWatch, abs(time - watch.position) > 0.5 {
            log.info("resume progressed; connection is alive")
            disarmResumeWatch()
        }
    }

    /// Saves progress and closes the player; the details page then offers Resume.
    func exitToDetails(reason: String) {
        guard !didFinish, !isExitingToDetails else { return }
        log.notice("leaving playback at \(self.lastKnownPosition)s: \(reason)")
        isExitingToDetails = true
        disarmResumeWatch()
        // Stop the engine's own recovery before the dismissal animation runs.
        engine.pause()
        dismiss(animated: true)
    }

    // MARK: Progress

    func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportProgress(ended: false) }
        }
    }

    func reportProgress(ended: Bool, paused: Bool? = nil) {
        let position = lastKnownPosition
        let duration = lastKnownDuration
        guard duration > 0, position > 0 else { return }
        let body = request.progressReport(position: position, duration: duration,
                                          paused: paused ?? (engine.state == .paused), ended: ended,
                                          sourcePath: streamPath)
        // Keep the request alive if the app is on its way into the background (sleep).
        let background = UIApplication.shared.beginBackgroundTask(withName: "progress")
        Task {
            await APIClient.shared.reportProgress(body)
            UIApplication.shared.endBackgroundTask(background)
        }
    }
}
