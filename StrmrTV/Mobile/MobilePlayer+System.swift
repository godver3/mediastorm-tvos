#if os(iOS)
import AVKit
import UIKit

/// The phone player and the system: Picture in Picture (AVKit's own button and the automatic start
/// when the app leaves the foreground) and audio that keeps playing in the background, as the Expo
/// player's `playInBackground`.
extension PlayerViewController: @MainActor AVPlayerViewControllerDelegate {
    func installPictureInPicture() {
        delegate = self
        allowsPictureInPicturePlayback = true
        canStartPictureInPictureAutomaticallyFromInline = true
        // Playback speed lives in the Settings menu, which goes through the engine (AVKit's own
        // speed control would set the AVPlayer's rate behind its back).
        speeds = []
        // The lock screen and Control Center show the title (the engine sets the item's metadata).
        updatesNowPlayingInfoCenter = true
    }

    // MARK: Picture in Picture

    /// The player stays presented under the PiP window: closing it is what ends the session, so
    /// PiP is for leaving the app (or keeping the video in a corner of the home screen), as Expo's.
    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
        _ playerViewController: AVPlayerViewController
    ) -> Bool { false }

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        log.notice("picture in picture starting at \(self.lastKnownPosition)s")
        engine.pictureInPictureActive = true
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        log.notice("picture in picture stopped at \(self.lastKnownPosition)s")
        engine.pictureInPictureActive = false
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              failedToStartPictureInPictureWithError error: any Error) {
        log.error("picture in picture failed: \(error.localizedDescription)")
        engine.pictureInPictureActive = false
    }

    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        // Still presented (it never dismisses for PiP); the app coming forward shows it again.
        completionHandler(presentingViewController != nil && !didFinish)
    }

    // MARK: Background

    /// Whether the engine keeps this session alive while the app is in the background: playing
    /// (background audio) or in a PiP window. A paused session is torn down by the engine after its
    /// grace window, and the player then leaves for the details page on return, as on the TV.
    var keepsPlayingInBackground: Bool {
        engine.pictureInPictureActive || engine.state == .playing
    }

    /// Back in the foreground: carry on when the engine kept the session, otherwise leave for
    /// the details page (Resume) as the TV does.
    func mobileReturnedToForeground() -> Bool {
        let alive = !engine.needsForegroundVideoRestore && (engine.state == .playing || engine.state == .paused)
        log.notice("foreground: session \(alive ? "kept" : "gone") (state \(String(describing: self.engine.state)))")
        return alive
    }
}

// MARK: Orientation

/// How the phone's player is oriented (Settings › Playback › Player Orientation, and the player's
/// Settings menu): held in landscape, held in portrait, or turning with the device.
enum PhonePlayerOrientation: String, CaseIterable, Identifiable {
    case landscape
    case portrait
    case device

    static let defaultsKey = "StrmrPlayerOrientation"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .landscape: String(localized: "Landscape")
        case .portrait: String(localized: "Portrait")
        case .device: String(localized: "Follow Device Rotation")
        }
    }

    var systemImage: String {
        switch self {
        case .landscape: "rectangle"
        case .portrait: "rectangle.portrait"
        case .device: "rectangle.landscape.rotate"
        }
    }

    var mask: UIInterfaceOrientationMask {
        switch self {
        case .landscape: .landscape
        case .portrait: .portrait
        case .device: .allButUpsideDown
        }
    }
}

extension EnginePlayerViewController {
    /// The phone's player orientation, kept across sessions (the Expo player's rotate button).
    /// Landscape until the viewer picks another. An iPad follows the device.
    static var phoneOrientationChoice: PhonePlayerOrientation {
        get { UserDefaults.standard.string(forKey: PhonePlayerOrientation.defaultsKey).flatMap(PhonePlayerOrientation.init) ?? .landscape }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PhonePlayerOrientation.defaultsKey) }
    }

    static var phoneOrientation: UIInterfaceOrientationMask { phoneOrientationChoice.mask }

    static var playerOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : phoneOrientation
    }

    /// What `enterPreferredOrientation` asks the scene for: the locked orientation, or (following
    /// the device) the way the phone is held now, so the player opens in it. Nil when the phone
    /// lies flat or its orientation is unknown: the scene then turns once the phone is tilted.
    static var phoneGeometryRequest: UIInterfaceOrientationMask? {
        guard phoneOrientationChoice == .device else { return phoneOrientation }
        // A device turned left shows its interface turned right.
        switch UIDevice.current.orientation {
        case .portrait: return .portrait
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return nil
        }
    }
}
#endif
