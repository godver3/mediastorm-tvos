#if os(iOS)
import AetherEngine
import AVFoundation
import UIKit

/// Subtitles on an AirPlay receiver.
///
/// The player draws every subtitle itself (`SubtitleOverlayView`, over the video on this device),
/// which an AirPlay receiver never sees: AirPlay carries only the AVPlayer's stream. While the
/// picture is on a receiver, the engine's native subtitle renditions (WebVTT in the served HLS
/// master) carry the picked text track instead, and the receiver draws it.
///
/// Those renditions stay off otherwise (`baseLoadOptions`): building them costs a second read of
/// the source, and AVKit picking one by itself had stalled playback on a bitmap track. So they are
/// turned on only once the picture leaves (in the load options when AirPlay is already up, by a
/// session-preserving reload once the engine's own AirPlay reload has settled when it starts
/// mid-session) and stay on for the rest of the session.
///
/// Limits, all the engine's: text tracks only (a PGS / VobSub track, and an online subtitle, which
/// is the app's own cues, stay on the phone's overlay); SDR only, since an HDR / Dolby Vision
/// receiver gets the media playlist, which carries no renditions (the overlay then stays on).
@MainActor
final class AirPlaySubtitleHandoff {
    private weak var player: PlayerViewController?
    private var timer: Timer?
    private var active = false
    private var correcting = false
    private var lastReading = false
    private var readingTicks = 0
    private var settledTicks = 0
    private var gaveUp = false
    private let log = AppLog(category: "airplay-subs")

    init(player: PlayerViewController) {
        self.player = player
    }

    /// Whether the audio route is a wireless AirPlay receiver right now (read at load).
    static var routeIsAirPlay: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    }

    func start() {
        guard timer == nil else { return }
        // AVPlayer's external-playback flag has no notification the app can hold across the
        // engine's item rebuilds; a once-a-second read is cheap and follows every rebuild.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let player else { return stop() }
        let external = !player.softwareSurfaceMounted && (player.player?.isExternalPlaybackActive ?? false)
        // AVPlayer's flag flickers while the engine rebuilds the item; act on a state held 2 s.
        if external == lastReading { readingTicks += 1 } else { lastReading = external; readingTicks = 1 }
        let engine = player.engine
        let settled = engine.state == .playing || engine.state == .paused
        settledTicks = settled ? settledTicks + 1 : 0
        if readingTicks >= 2, external != active {
            active = external
            log.notice("picture \(external ? "on an AirPlay receiver: subtitles go with it" : "back on this device")")
            engine.setNativeSubtitleRendering(external)
        }
        // 6 s: past the engine's own check that the receiver took the master it was given
        // (`airPlayProgressWatchdogSeconds`, 5 s), whose fallback is one more rebuild.
        if active, !player.nativeSubtitlesPrepared, !correcting, !gaveUp, settledTicks >= 6, !player.didFinish {
            addRenditions()
        }
        updateOverlay()
    }

    /// The session started without the renditions: add them with a session-preserving reload.
    ///
    /// Only once the engine's own AirPlay reload (its LAN address for the receiver) has finished and
    /// playback has held for a few seconds: a reload started while that one is in flight supersedes
    /// it, and the engine then served the rebuilt item on 127.0.0.1, which the receiver cannot
    /// reach (device log 2026-11-10: playback wedged and the source auto-switched).
    private func addRenditions() {
        guard let player else { return }
        let engine = player.engine
        correcting = true
        Task { [weak self] in
            do {
                try await engine.reloadAtCurrentPosition { $0.prepareNativeSubtitles = true }
                player.nativeSubtitlesPrepared = true
                self?.log.notice("native subtitle renditions on (\(engine.nativeSubtitleTracks.count) text tracks)")
            } catch {
                // Not retried: a refusal means this session cannot be rebuilt in place.
                self?.gaveUp = true
                self?.log.error("native subtitle renditions refused: \(error.localizedDescription)")
            }
            self?.correcting = false
            if self?.active == true { engine.setNativeSubtitleRendering(true) }
        }
    }

    /// The phone's overlay steps aside while the receiver draws the same track, and stays up for a
    /// track the receiver cannot get (bitmap, online, or no renditions served to an HDR receiver).
    private func updateOverlay() {
        guard let player else { return }
        let hide = active && player.receiverDrawsActiveSubtitle
        if player.subtitleOverlay.isHidden != hide { player.subtitleOverlay.isHidden = hide }
    }
}

extension PlayerViewController {
    /// Whether the AirPlay receiver has the active subtitle as a native rendition.
    var receiverDrawsActiveSubtitle: Bool {
        guard nativeSubtitlesPrepared, engine.nativeSubtitleRenditionsServed, !engine.nativeSubtitleTracks.isEmpty,
              let id = activeSubtitle, id != OnlineSubtitles.trackID,
              let track = engine.subtitleTracks.first(where: { $0.id == id }) else { return false }
        return !OnlineSubtitles.isBitmapCodec(track.codec)
    }
}
#endif
