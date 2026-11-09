#if os(iOS)
import UIKit

/// The live player's Cast item: the channel playing goes to the chosen TV and the player
/// closes (which stops its own session first, so the provider's stream slot is free).
///
/// AVKit's iOS chrome shows no custom menu items, so the cast button sits in the VOD player's
/// menu row (`MobilePlayerControls`, over AVKit's top bar and fading with it). A channel with
/// catch-up draws its own programme bar instead, whose row lists the Cast item.
extension LivePlayerViewController {
    func installMobileLiveControls() {
        guard !usesProgrammeBar else { return }
        let controls = mobileControls
        Self.fill(controls, in: view)
        view.addSubview(controls)
        controls.onClose = { [weak self] in self?.dismiss(animated: true) }
        controls.setCastAction { [weak self] in self?.openCastPicker() }
        // The row is an extra over AVKit's chrome: without that chrome (the software route) it
        // stays hidden rather than putting a tap recognizer on the player's view.
        mobileChromeTracker.allowsFallback = false
        mobileChromeTracker.start()
    }

    /// AVKit can add its own views above the controls as its chrome builds; keep them on top.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard mobileControls.superview === view, view.subviews.last !== mobileControls else { return }
        view.bringSubviewToFront(mobileControls)
    }

    var castMenuItems: [UIMenuElement] {
        let cast = UIAction(title: String(localized: "Cast"), image: CastPresenter.castIcon(pointSize: 21)) { [weak self] _ in
            self?.openCastPicker()
        }
        return [cast]
    }

    func openCastPicker() {
        CastPresenter.showPicker(from: self) { [weak self] device in self?.handOffToCast(device) }
    }

    private func handOffToCast(_ device: CastDevice) {
        let channel = channel
        let airing = program.flatMap { $0.isAiring(at: Date()) ? $0 : nil }
            ?? catchupPrograms.first { $0.isAiring(at: Date()) }
        log.notice("handing \(channel.name) off to \(device.name)")
        engine.pause()
        dismiss(animated: true) {
            Task { await CastController.shared.startLive(on: device, channel: channel, program: airing) }
        }
    }
}
#endif
