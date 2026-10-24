import Foundation

/// The direct → HLS fallback, as the Expo app's `useLiveDirectRecovery` does it. Some
/// providers' streams play only through the server's HLS session: when a direct stream fails
/// before its first frame the channel is opened once more with `format=hls`. Once that has
/// played for ten seconds the choice is remembered for the live source (`LiveHLSPreference`),
/// and later tunes of it ask for HLS at once.
///
/// A direct stream that never errors but never shows a frame either (a provider that answers
/// and then sends nothing, behind a server that already returned 200) counts as failed after
/// `directStartDeadline`; the server's own first-byte deadline is shorter, so a current server
/// usually reports the failure first.
extension LivePlayerViewController {
    static let directStartDeadline: TimeInterval = 25

    enum HLSMode {
        /// As the source is set up (direct or HLS).
        case asConfigured
        /// HLS, remembered for this source on this device.
        case remembered
        /// HLS after this channel's direct stream failed; not yet remembered.
        case fallback
    }

    /// Whether this tune asks for HLS: after a direct failure, or as the source's remembered choice.
    func hlsForTune() async -> Bool {
        if hlsMode != .asConfigured { return true }
        guard let scope = await LiveHLSPreference.scope(for: channel, wait: false),
              LiveHLSPreference.prefersHLS(scope) else { return false }
        log.notice("live hls: remembered for this source")
        hlsMode = .remembered
        return true
    }

    /// A direct stream that never played: tunes once more as HLS. False when that doesn't
    /// apply (an HLS tune, one that played, or the fallback already tried).
    func fallBackToHLS(_ reason: String) -> Bool {
        guard !didFinish, tuneIsDirect, !tunePlayed, hlsMode == .asConfigured else { return false }
        log.notice("live hls: direct stream failed before playing (\(reason)); retrying as hls")
        hlsMode = .fallback
        // Close the direct stream's provider connection before the session opens another.
        engine.stop()
        tune(after: 0.3)
        return true
    }

    /// Arms the no-first-frame deadline for a direct tune.
    func startDirectDeadline() {
        directStartTimer?.invalidate()
        guard tuneIsDirect else { return }
        directStartTimer = Timer.scheduledTimer(withTimeInterval: Self.directStartDeadline, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.tunePlayed else { return }
                let reason = "no first frame in \(Int(Self.directStartDeadline)) s"
                guard !self.fallBackToHLS(reason) else { return }
                self.log.error("live direct stream: \(reason)")
            }
        }
    }

    /// The fallback's first frame: still playing ten seconds on, the choice is remembered.
    func startHLSProof() {
        hlsProofTimer?.invalidate()
        guard hlsMode == .fallback else { return }
        hlsProofTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.confirmHLS() }
        }
    }

    private func confirmHLS() {
        guard !didFinish, hlsMode == .fallback, tunePlayed, case .playing = engine.state else { return }
        // Once per player: a late error can't remember another channel's source.
        hlsMode = .remembered
        Task { [channel, log] in
            guard let scope = await LiveHLSPreference.scope(for: channel, wait: true) else {
                log.notice("live hls: playing, but the source can't be remembered")
                return
            }
            LiveHLSPreference.remember(scope)
            log.notice("live hls: remembered for source \(scope.sourceID)")
        }
    }
}
