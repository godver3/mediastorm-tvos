import AetherEngine
import Foundation

/// The direct → HLS fallback, as the Expo app's `useLiveDirectRecovery` does it. Some
/// providers' streams play only through the server's HLS session: when a direct stream fails
/// before its first frame the channel is opened once more with `format=hls`. Once that has
/// played without a stall for `hlsProofDuration` the choice is remembered for the live source
/// (`LiveHLSPreference`), and later tunes of it ask for HLS at once.
///
/// A direct stream that never errors but never shows a frame either (a provider that answers
/// and then sends nothing, behind a server that already returned 200) counts as failed after
/// `directStartDeadline`; the server's own first-byte deadline is shorter, so a current server
/// usually reports the failure first. A stream that has opened and is being demuxed is only
/// slow, not dead: a provider delivering a 4K channel below real time fills the join's
/// holdback late (18 s of media took ~30 s on a reported Sportsnet 4K line), so it gets until
/// `directStartSlowDeadline`. HLS reads the same provider and can't fix that, so a fallback
/// reached through a deadline is tried for this tune but never remembered for the source.
extension LivePlayerViewController {
    static let directStartDeadline: TimeInterval = 25
    static let directStartSlowDeadline: TimeInterval = 60
    /// How long the fallback must play with no stall before it is remembered.
    static let hlsProofDuration: TimeInterval = 30

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
        guard let scope = await LiveHLSPreference.scope(for: channel),
              LiveHLSPreference.prefersHLS(scope) else { return false }
        log.notice("live hls: remembered for this source")
        hlsMode = .remembered
        return true
    }

    /// A direct stream that never played: tunes once more as HLS. False when that doesn't
    /// apply (an HLS tune, one that played, or the fallback already tried). `rememberable`:
    /// the direct stream failed outright, so a working fallback may be kept for the source.
    func fallBackToHLS(_ reason: String, rememberable: Bool = true) -> Bool {
        guard !didFinish, tuneIsDirect, !tunePlayed, hlsMode == .asConfigured else { return false }
        log.notice("live hls: direct stream failed before playing (\(reason)); retrying as hls")
        hlsMode = .fallback
        hlsFallbackRememberable = rememberable
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
            MainActor.assumeIsolated { self?.directDeadlinePassed() }
        }
    }

    private func directDeadlinePassed() {
        guard !tunePlayed else { return }
        if directStreamIsProgressing {
            let more = Self.directStartSlowDeadline - Self.directStartDeadline
            log.notice("live direct: no first frame in \(Int(Self.directStartDeadline)) s but the stream is being demuxed; waiting \(Int(more)) s more")
            directStartTimer = Timer.scheduledTimer(withTimeInterval: more, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.directStartFailed(after: Self.directStartSlowDeadline) }
            }
            return
        }
        directStartFailed(after: Self.directStartDeadline)
    }

    private func directStartFailed(after deadline: TimeInterval) {
        guard !tunePlayed else { return }
        let reason = "no first frame in \(Int(deadline)) s"
        guard !fallBackToHLS(reason, rememberable: false) else { return }
        log.error("live direct stream: \(reason)")
    }

    /// The source opened and its streams were probed and routed, and the reader isn't stalled:
    /// what's left is the first live window filling.
    private var directStreamIsProgressing: Bool {
        guard let checkpoint = engine.startupProgress?.checkpoint, checkpoint >= .routed else { return false }
        switch engine.playbackPhase {
        case .stalled, .error, .ended, .idle: return false
        default: return true
        }
    }

    /// The fallback's first frame: still playing with no stall `hlsProofDuration` on, the
    /// choice is remembered.
    func startHLSProof() {
        hlsProofTimer?.invalidate()
        hlsProofStalled = false
        guard hlsMode == .fallback else { return }
        guard hlsFallbackRememberable else {
            log.notice("live hls: fallback after a slow direct start; not remembered for the source")
            return
        }
        hlsProofTimer = Timer.scheduledTimer(withTimeInterval: Self.hlsProofDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.confirmHLS() }
        }
    }

    /// A stall while the fallback is on probation: it isn't working well enough to keep.
    func noteHLSProofDistress(_ distress: LivePlaybackTelemetry.Distress) {
        guard distress == .stall, hlsProofTimer?.isValid == true, !hlsProofStalled else { return }
        hlsProofStalled = true
        log.notice("live hls: fallback stalled while on probation; not remembered for the source")
    }

    private func confirmHLS() {
        guard !didFinish, hlsMode == .fallback, tunePlayed, !hlsProofStalled,
              case .playing = engine.state else { return }
        // Once per player: a late error can't remember another channel's source.
        hlsMode = .remembered
        Task { [channel, log] in
            guard let scope = await LiveHLSPreference.scope(for: channel) else {
                log.notice("live hls: playing, but the source can't be remembered")
                return
            }
            LiveHLSPreference.remember(scope)
            log.notice("live hls: remembered for source \(scope.sourceID)")
        }
    }
}
