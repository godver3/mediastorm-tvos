#if os(iOS)
import Foundation
import UIKit

/// The two ways a cast starts, as in the Expo app: Cast on the details page plays the title
/// (through the same prequeue / library resolve as Play) on the device instead of the phone,
/// and the player's cast button hands what is playing over at the current position.
extension CastController {
    /// Details page: the picker chose `device`; `play` then starts the usual resolve, whose
    /// stream `claim` takes. Disarmed if that resolve ends without a stream (cancelled, failed)
    /// or nothing resolves within a minute (Play opened a Versions list that was closed).
    func arm(_ device: CastDevice, play: () -> Void) {
        handoff = (device, Date())
        handoffWatch = PlaybackCoordinator.shared.$resolving.dropFirst().sink { [weak self] resolving in
            guard resolving == nil else { return }
            Task { @MainActor in self?.disarm() }
        }
        play()
    }

    private func disarm() {
        handoff = nil
        handoffWatch = nil
    }

    /// `PlaybackCoordinator` resolved a stream: true when an armed cast takes it.
    func claim(_ request: PlaybackRequest, path: String, tracks: TrackPreferences) -> Bool {
        guard let handoff, Date().timeIntervalSince(handoff.armed) < 60 else {
            disarm()
            return false
        }
        disarm()
        // Text subtitles only: a receiver shows a WebVTT rendition, not a bitmap track.
        let subtitle = tracks.subtitle.flatMap { $0.bitmap == true ? nil : $0 } ?? tracks.selection?.textSubtitle
        let language = subtitle.flatMap { $0.languageCode ?? $0.language }
        Task {
            await start(on: handoff.device, request: request, path: path, position: request.startPosition ?? 0,
                        audio: tracks.audioStreamIndex, subtitle: subtitle?.streamIndex, subtitleLanguage: language)
        }
        return true
    }
}

extension PlayerViewController {
    /// The cast button in the player's menu row.
    func openCastPicker() {
        CastPresenter.showPicker(from: self) { [weak self] device in self?.handOffToCast(device) }
    }

    /// Pauses here, saves the position, closes the player and continues on `device` from there,
    /// with the audio and (embedded text) subtitle picked in the player.
    private func handOffToCast(_ device: CastDevice) {
        let position = max(engine.currentTime, lastKnownPosition)
        let audio = pendingAudioPick ?? engine.activeAudioTrackIndex ?? tracks.audioStreamIndex
        let subtitleTrack = activeSubtitle.flatMap { id in
            subtitleTracks.first { $0.id == id && $0.id >= 0 && !$0.isExternal && !Self.isBitmapCodec($0.codec) }
        }
        log.notice("handing off to \(device.name) at \(Int(position))s")
        engine.pause()
        reportProgress(ended: false, paused: true)
        let request = request, path = streamPath
        dismiss(animated: true) {
            Task {
                await CastController.shared.start(on: device, request: request, path: path, position: position,
                                                  audio: audio, subtitle: subtitleTrack?.id,
                                                  subtitleLanguage: subtitleTrack?.language)
            }
        }
    }

    private static func isBitmapCodec(_ codec: String) -> Bool {
        ["hdmv_pgs_subtitle", "pgssub", "dvd_subtitle", "dvdsub", "dvb_subtitle", "dvbsub", "xsub"].contains(codec.lowercased())
    }
}
#endif
