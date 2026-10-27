import UIKit

/// Skip Intro / Skip Recap / Next Episode buttons, and starting the next episode.
extension PlayerViewController {
    // MARK: Skip segments

    /// Shows Skip Intro / Skip Recap / Next Episode in the transport bar while playback is
    /// inside a segment (on the software route, in its HUD).
    func updateSkipAction(at time: Double) {
        skipSegments.refresh(duration: engine.duration, chapters: engine.mediaChapters)
        let found = skipSegments.active(at: time)
        let segment = found == dismissedSegment ? nil : found
        guard segment != activeSegment else { return }
        activeSegment = segment
        stopCountdown()
        if segment?.type == "outro", nextEpisode != nil, creditsAutoSkip {
            startCountdown()
        }
        refreshSkipAction()
    }

    private func refreshSkipAction() {
        let hadAction = !contextualActions.isEmpty
        defer {
            // Removing the button while it holds focus left AVKit with nothing focused, and the
            // remote no longer brought the transport bar up.
            if hadAction, contextualActions.isEmpty {
                setNeedsFocusUpdate()
                updateFocusIfNeeded()
            }
        }
        contextualActions = activeSegment.map { segment in
            [SkipSegments.action(
                for: segment, next: nextEpisode, countdown: countdown?.remaining,
                skip: { [weak self] end in
                    guard let self else { return }
                    Task { await self.engine.seek(to: min(end, self.engine.duration)) }
                },
                playNext: { [weak self] next in self?.playNext(next) }
            )]
        } ?? []
        // The software route has no AVKit chrome to show it; its HUD draws the same action.
        softwareHUD.setAction(contextualActions.first)
    }

    /// Menu over the skip button hides AVKit's contextual-action presentation but leaves the
    /// action set, and while it stays set the remote can't bring the transport bar back up.
    /// Drop the action and don't offer it again for this segment.
    func dismissSkipActionIfMenu(_ presses: Set<UIPress>) {
        guard presses.contains(where: { $0.type == .menu }) else { return }
        dismissSkipActionIfMenu()
    }

    /// Menu on the software route's Skip capsule (the HUD routes it here).
    func dismissSkipActionIfMenu() {
        guard let activeSegment, !contextualActions.isEmpty else { return }
        log.notice("skip button dismissed (\(activeSegment.type))")
        dismissedSegment = activeSegment
        self.activeSegment = nil
        stopCountdown()
        refreshSkipAction()
    }

    // MARK: Up next

    func prefetchNextIfNear(_ time: Double) {
        guard !didPrefetchNext, let nextEpisode, engine.duration > 0 else { return }
        guard time >= engine.duration * Self.prefetchFraction || activeSegment?.type == "outro" else { return }
        didPrefetchNext = true
        log.notice("prefetching \(nextEpisode.episode?.code ?? "?") at \(Int(time))s of \(Int(self.engine.duration))s")
        PlaybackCoordinator.shared.prefetch(nextEpisode)
    }

    /// Counts the Next Episode button down while the credits play; pausing holds it and
    /// seeking out of the credits cancels it.
    private func startCountdown() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickCountdown() }
        }
        countdown = (Self.countdownSeconds, timer)
        log.notice("credits: next episode in \(Self.countdownSeconds)s")
    }

    private func tickCountdown() {
        guard let current = countdown, engine.state == .playing else { return }
        let remaining = current.remaining - 1
        guard remaining > 0 else {
            stopCountdown()
            if let nextEpisode { playNext(nextEpisode) }
            return
        }
        countdown = (remaining, current.timer)
        refreshSkipAction()
    }

    func stopCountdown() {
        countdown?.timer.invalidate()
        countdown = nil
    }

    /// Closes this episode (saving it as finished) and starts the next over the loading art.
    func playNext(_ next: PlaybackRequest) {
        guard !isAdvancing, !didFinish else { return }
        isAdvancing = true
        stopCountdown()
        log.notice("playing next: \(next.episode?.code ?? "?")")
        dismiss(animated: true) { PlaybackCoordinator.shared.play(next) }
    }
}
