import AetherEngine
import Foundation

/// How deep behind the live edge a channel joins. Channels join with `.fastZap`, whose holdback
/// collapses to the source's keyframe cadence (a few seconds). A source that delivers in bursts
/// (an IPTV restream that hands over several segments every 8 to 9 s) outruns that buffer:
/// AVPlayer reports the engine's playlist unchanged for longer than 1.5 target durations
/// (-12888), runs dry and the audio hiccups. The first time that happens on the engine's own
/// playlist (the loopback route; on the server's HLS route the join profile plays no part) the
/// channel is tuned again with `.standard`, about 18 s of holdback. `.standard` costs 10 to 18 s
/// more to tune (its first playlist waits for the full holdback, filled in real time), so one
/// blip doesn't stick: the choice is remembered for the live source (`LiveHLSPreference`) only
/// when a tune of it runs dry a second time, and later tunes of it then join that way at once.
extension LivePlayerViewController {
    /// Distress counts from this long after the first frame: a fast join may rebuffer once
    /// while its first window fills.
    static let joinDistressGrace: TimeInterval = 10

    /// The join for this tune: standard once switched, or as the source's remembered choice.
    func joinProfileForTune() async -> LiveJoinProfile {
        if standardJoin { return .standard }
        guard let scope = await LiveHLSPreference.scope(for: channel),
              LiveHLSPreference.prefersStandardJoin(scope) else { return .fastZap }
        log.notice("live join: standard, remembered for this source")
        standardJoin = true
        return .standard
    }

    func noteJoinDistress(_ distress: LivePlaybackTelemetry.Distress) {
        guard !didFinish, !standardJoin, let firstFrameAt, engine.videoRoute == .loopback else { return }
        guard Date().timeIntervalSince(firstFrameAt) >= Self.joinDistressGrace else { return }
        log.notice("live join: fast join running dry (\(distress)); retuning with the standard join")
        standardJoin = true
        Task { [channel, log] in
            guard let scope = await LiveHLSPreference.scope(for: channel) else { return }
            if LiveHLSPreference.noteFastJoinRanDry(scope) {
                log.notice("live join: standard remembered for source \(scope.sourceID)")
            } else {
                log.notice("live join: first time source \(scope.sourceID) ran dry; not remembered yet")
            }
        }
        engine.stop()
        tune(after: 0.3)
    }
}
