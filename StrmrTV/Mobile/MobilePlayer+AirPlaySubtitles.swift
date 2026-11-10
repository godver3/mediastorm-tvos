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
/// session-preserving reload when it starts mid-session) and stay on for the rest of the session.
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
        if external != active {
            active = external
            log.notice("picture \(external ? "on an AirPlay receiver: subtitles go with it" : "back on this device")")
            if external { handOff() } else { player.engine.setNativeSubtitleRendering(false) }
        }
        updateOverlay()
    }

    /// The renditions must be in the session before the receiver can be given one.
    private func handOff() {
        guard let player else { return }
        let engine = player.engine
        if player.nativeSubtitlesPrepared {
            engine.setNativeSubtitleRendering(true)
            return
        }
        guard !correcting else { return }
        correcting = true
        Task { [weak self] in
            // The engine rebuilds the item itself on the AirPlay edge (its LAN address); let that
            // settle before asking for another.
            for _ in 0..<20 where engine.state == .loading || engine.state == .seeking {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self, let player = self.player, self.active, !player.didFinish else {
                self?.correcting = false
                return
            }
            do {
                try await engine.reloadAtCurrentPosition { $0.prepareNativeSubtitles = true }
                player.nativeSubtitlesPrepared = true
                self.log.notice("native subtitle renditions on (\(engine.nativeSubtitleTracks.count) text tracks)")
            } catch {
                self.log.error("native subtitle renditions refused: \(error.localizedDescription)")
            }
            self.correcting = false
            if self.active { engine.setNativeSubtitleRendering(true) }
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
