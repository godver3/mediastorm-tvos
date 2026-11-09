#if os(iOS)
import UIKit

/// The recording player's phone controls (`MobilePlayerControls`), in place of the TV's HUD.
///
/// A growing recording always gets them as the whole transport (AVKit would draw its open-ended
/// playlist as a live stream, as on the TV), with a small REC capsule in the top row that fades
/// with the rest; a finished one gets them only on the software route, and otherwise just the menu
/// row over AVKit's chrome. Seeks go through the player's `seekPlayback`, which keeps a growing
/// recording's seeks within the playlist so far.
extension RecordingPlayerViewController {
    func installMobileRecordingControls() {
        let controls = mobileControls
        Self.fill(controls, in: view)
        view.addSubview(controls)
        controls.onClose = { [weak self] in self?.dismiss(animated: true) }
        controls.onPlayPause = { [weak self] in self?.engine.togglePlayPause() }
        controls.onSkip = { [weak self] delta in self?.seek(by: delta) }
        controls.onScrub = { [weak self] time, ended in self?.mobileScrub(to: time, ended: ended) }
        controls.setMenus([recordingSettingsMenu()])
        if growing {
            showsPlaybackControls = false
            controls.transport.setBadge(Self.recBadgeText)
        }
        controls.setOwnsTransport(ownsTransport)
        mobileChromeTracker.start()
    }

    /// AVKit can add its own views above the controls as its chrome builds; keep them on top.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard mobileControls.superview === view, view.subviews.last !== mobileControls else { return }
        view.bringSubviewToFront(mobileControls)
    }

    /// The software surface came or went: the controls own the transport on it (or always, growing).
    func mobileSoftwareSurfaceChanged() {
        mobileControls.setOwnsTransport(ownsTransport)
        view.bringSubviewToFront(mobileControls)
    }

    /// The scrubber moved: the time follows the finger; lifting it seeks there.
    private func mobileScrub(to time: Double, ended: Bool) {
        scrubTarget = time
        mobileControls.transport.showPreview(time: time, image: nil, hasThumbnails: false)
        guard ended else { return }
        log.info("touch scrub to \(Int(time))s of \(Int(transportDuration))s")
        Task { [weak self] in
            guard let self else { return }
            await seekPlayback(to: time)
            if scrubTarget == time { scrubTarget = nil }
            try? await Task.sleep(for: .milliseconds(600))
            if scrubTarget == nil { mobileControls.transport.hidePreview() }
        }
    }

    /// Settings: Stream Info (the TV's swipe-down tab).
    private func recordingSettingsMenu() -> UIMenu {
        let info = UIAction(title: String(localized: "Stream Info"), image: UIImage(systemName: "info.circle")) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.presentRecordingStreamInfo() }
        }
        let menu = UIMenu(title: "", image: UIImage(systemName: "gearshape"), children: [info])
        menu.accessibilityLabel = String(localized: "Settings")
        return menu
    }

    private func presentRecordingStreamInfo() {
        guard presentedViewController == nil, !didFinish else { return }
        let info = Self.streamInfo(base: streamInfoBase, engine: engine)
        weak var page: UIViewController?
        let sheet = UIViewController.mobilePlayerSheet(
            MobileStreamInfoView(info: info, onClose: { page?.dismiss(animated: true) }),
            onSwipeDismiss: {})
        page = sheet
        present(sheet, animated: true)
    }
}
#endif
