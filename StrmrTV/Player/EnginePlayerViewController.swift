import AetherEngine
import AVKit
import Combine
import UIKit

/// What the VOD and live players share: stock tvOS player chrome over AetherEngine, the
/// software (dav1d / VP9) route's own surface, and the overlay every subtitle is drawn in.
/// The engine owns demux/decode; AVKit only sees the engine's AVPlayer.
class EnginePlayerViewController: AVPlayerViewController {
    let engine: AetherEngine
    let log: AppLog
    var cancellables = Set<AnyCancellable>()
    let settingsHider = TransportSettingsHider()
    let subtitleOverlay = SubtitleOverlayView()
    let softwareSurface = AetherPlayerView()
    private(set) var softwareSurfaceMounted = false
    /// The display's Match Content setting, read when the player appears.
    var matchContent = false
    /// The info panel's artwork load (`+InfoPanel`); internal for that file.
    var infoArtworkTask: Task<Void, Never>?
    /// The Stream info tab and its session-fixed rows (`+StreamInfo`); internal for that file.
    lazy var streamInfoTab = StreamInfoViewController()
    var streamInfoBase = StreamInfo()

    init(engine: AetherEngine, logCategory: String) {
        self.engine = engine
        log = AppLog(category: logCategory)
        super.init(nibName: nil, bundle: nil)
        // Over, not full screen: .fullScreen removes the SwiftUI hierarchy underneath while the
        // player is up, and it came back rebuilt (navigation popped to Home) on dismissal.
        modalPresentationStyle = .overFullScreen
        // Fades in over the loading art rather than sliding up from below it.
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        showsPlaybackControls = true
        // The engine is the sole display-criteria writer (HDR / DV / frame-rate match);
        // AVKit's automatic criteria would race it.
        appliesPreferredDisplayCriteriaAutomatically = false
        allowsPictureInPicturePlayback = false

        // Native path: hand AVKit the engine's AVPlayer. nil on the software route, which
        // renders into `softwareSurface` instead.
        engine.$currentAVPlayer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] avPlayer in self?.player = avPlayer }
            .store(in: &cancellables)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        finish()
    }

    /// The Stream tab's rows changed (`+StreamInfo`); the software route's HUD shows the summary.
    func streamInfoDidChange(_ info: StreamInfo) {}

    /// Tears the session down once the player has been dismissed. Subclasses override it.
    func finish() {}

    /// Where overlays go: AVKit's content overlay, above the video.
    var overlayHost: UIView { contentOverlayView ?? view! }

    /// Sizes `subview` to `host` and keeps it that way.
    static func fill(_ subview: UIView, in host: UIView) {
        subview.frame = host.bounds
        subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    /// Mounts (or removes) the software route's surface at the bottom of the overlay host and
    /// binds the engine to it. AVKit has no AVPlayer to drive on that route, so its chrome
    /// would only show an idle spinner; it is hidden and the remote is handled in
    /// `pressesBegan`. Returns false when nothing changed.
    @discardableResult
    func mountSoftwareSurface(_ mounted: Bool) -> Bool {
        guard mounted != softwareSurfaceMounted else { return false }
        if mounted {
            Self.fill(softwareSurface, in: overlayHost)
            overlayHost.insertSubview(softwareSurface, at: 0)
            engine.bind(view: softwareSurface)
        } else {
            engine.unbind(view: softwareSurface)
            softwareSurface.removeFromSuperview()
        }
        softwareSurfaceMounted = mounted
        showsPlaybackControls = !mounted
        return true
    }

    /// Options every session starts from; callers add their own.
    func baseLoadOptions() -> LoadOptions {
        var options = LoadOptions()
        options.httpHeaders = APIClient.shared.mediaHeaders
        options.matchContentEnabled = matchContent
        // Fallback when the backend expresses no audio preference; an explicit stream index
        // (the profile's resolved pick) wins over this.
        options.preferredAudioLanguages = TrackPreferences.deviceLanguages
        // Every subtitle is drawn by `SubtitleOverlayView` (AetherEngine's fullscreen design), so
        // no native renditions: AVKit selecting one stalled playback on a bitmap track's empty
        // OCR rendition, and building them costs a second source read.
        options.prepareNativeSubtitles = false
        return options
    }
}
