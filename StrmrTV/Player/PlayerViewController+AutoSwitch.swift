import AetherEngine
import UIKit

// MARK: Auto Switch
//
// Moves a movie or episode to the next ranked source by itself when the server reports this
// one broken or too slow (`migrationRequested` on a progress reply), or `StallWatch` sees
// playback stuck or stalling again and again. The next source is resolved while this one is
// still up, then played from the same position with the same languages, as a Switch Source pick.
// Sources already tried are carried on the request, so a switch never goes back to one; after
// `autoSwitchLimit` switches it stops trying. Settings › Playback › Auto Switch Sources turns it off.

/// The player's Auto Switch state.
struct AutoSwitchState {
    var watch = StallWatch()
    var timer: Timer?
    var isSwitching = false
    /// Sources that failed to resolve on an earlier try from this player.
    var failed: Set<String> = []
}

extension PlayerViewController {
    static let autoSwitchLimit = 3
    /// Sources resolved per try before giving up on this one.
    static let autoSwitchCandidates = 5
    /// Stalls this close to the end aren't worth a switch; the credits are rolling.
    static let autoSwitchEndMargin: Double = 60

    /// From the start of loading, so a source that never starts is caught too.
    func startAutoSwitchWatch() {
        guard request.libraryVersion == nil, !engine.isLive else { return }
        autoSwitchState.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleAutoSwitchWatch() }
        }
    }

    func stopAutoSwitchWatch() {
        autoSwitchState.timer?.invalidate()
        autoSwitchState.timer = nil
    }

    private func sampleAutoSwitchWatch() {
        let position = engine.currentTime
        let nearEnd = lastKnownDuration > 0 && position > lastKnownDuration - Self.autoSwitchEndMargin
        // A resume after a long pause has its own recovery (`armResumeWatch`); a page over the
        // player (a menu, the source list) is the viewer's.
        let active = (engine.state == .playing || engine.state == .loading) && !isInBackground
            && resumeWatch == nil && presentedViewController == nil && subtitleSearch == nil && !nearEnd
        if let trigger = autoSwitchState.watch.sample(position: position, active: active) {
            autoSwitch(because: trigger.reason)
        }
    }

    /// The stream's state for the progress heartbeat.
    func streamHealth() -> StreamHealth {
        let bitrate = engine.sourceVideoBitrate
        return StreamHealth(buffering: engine.isBuffering,
                            bufferAhead: engine.liveTelemetry?.forwardBufferSeconds,
                            requiredMbps: bitrate > 0 ? Double(bitrate) / 1_000_000 : nil)
    }

    /// Resolves the next untried source and switches to it; with none left, stays put.
    func autoSwitch(because reason: String) {
        guard AutoSwitchSettingsStore.shared.enabled, !autoSwitchState.isSwitching, request.libraryVersion == nil,
              !didFinish, !isAdvancing, !isExitingToDetails, !engine.isLive else { return }
        guard request.autoSwitchCount < Self.autoSwitchLimit else {
            log.notice("auto switch: \(reason); already switched \(self.request.autoSwitchCount) times, staying")
            autoSwitchState.watch.reset()
            return
        }
        autoSwitchState.isSwitching = true
        var tried = request.autoSwitchTried.union(Self.keys(currentSource)).union(autoSwitchState.failed)
        log.notice("auto switch: \(reason) at \(Int(self.lastKnownPosition))s on "
                   + "\(self.currentSource.releaseName ?? self.currentSource.streamPath ?? "?")")
        subtitleStatus.show(String(localized: "Switching to another source…"), hideAfter: nil)
        Task { [weak self] in
            guard let self else { return }
            let list = sourceList ?? SourceSwitchList(request: request)
            sourceList = list
            let results = (try? await list.load()) ?? []
            let candidates = SourceSearch.ordered(results).filter { result in
                !SourceSwitch.matches(result, currentSource) && tried.isDisjoint(with: Self.keys(result))
                    && !["unhealthy", "not_cached"].contains((list.health[result.index] ?? result.health)?.state ?? "")
            }
            for candidate in candidates.prefix(Self.autoSwitchCandidates) {
                guard !didFinish, !isExitingToDetails, !isAdvancing else { return }
                tried.formUnion(Self.keys(candidate))
                do {
                    let resolved = try await APIClient.shared.resolveSource(
                        candidate, titleID: request.title.titleID, startOffset: lastKnownPosition)
                    guard !didFinish, !isExitingToDetails, !isAdvancing else { return }
                    return switchAutomatically(to: candidate, resolved: resolved, tried: tried)
                } catch {
                    log.notice("auto switch: \(SourceSwitch.releaseName(candidate)) didn't resolve: \(error.localizedDescription)")
                }
            }
            log.notice("auto switch: no other source to switch to (\(results.count) sources)")
            subtitleStatus.show(String(localized: "No other source to switch to"), hideAfter: 4)
            autoSwitchState.failed = tried
            autoSwitchState.watch.reset()
            autoSwitchState.isSwitching = false
        }
    }

    private func switchAutomatically(to result: SourceResult, resolved: (path: String, tracks: TrackSelection?),
                                     tried: Set<String>) {
        isAdvancing = true
        let position = lastKnownPosition
        let carry = currentTrackCarry()
        log.notice("auto switch: -> \(SourceSwitch.releaseName(result)) (\(result.serviceType)) at \(Int(position))s")
        var next = PlaybackRequest(title: request.title, episode: request.episode,
                                   start: position > 0 ? .seconds(position) : nil,
                                   following: request.following, artwork: request.artwork)
        next.autoSwitchTried = tried
        next.autoSwitchCount = request.autoSwitchCount + 1
        subtitleStatus.hide()
        dismiss(animated: true) {
            PlaybackCoordinator.shared.play(next, source: result, carry: carry, resolved: resolved)
        }
    }

    private static func keys(_ source: SourceSwitch.Current) -> Set<String> {
        Set([source.guid, source.releaseName].compactMap(normalizedKey))
    }

    private static func keys(_ result: SourceResult) -> Set<String> {
        Set([result.id, SourceSwitch.releaseName(result)].compactMap(normalizedKey))
    }

    private static func normalizedKey(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else { return nil }
        return value
    }
}
