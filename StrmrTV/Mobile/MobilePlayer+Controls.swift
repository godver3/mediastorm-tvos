#if os(iOS)
import AVKit
import SwiftUI
import UIKit

/// The VOD player's phone controls (`MobilePlayerControls`): mounted over AVKit's chrome on the
/// native route and as the whole transport on the software route, fed the same menus and skip
/// action the TV's transport bar gets. Picture in Picture and the pages the menus open (as sheets)
/// are in `MobilePlayer+System` and `MobilePlayer+Sheets`.
extension PlayerViewController {
    func installMobileControls() {
        let controls = mobileControls
        Self.fill(controls, in: view)
        view.addSubview(controls)
        controls.onClose = { [weak self] in self?.dismiss(animated: true) }
        controls.onPlayPause = { [weak self] in self?.engine.togglePlayPause() }
        controls.onSkip = { [weak self] delta in self?.skip(by: delta) }
        controls.onScrub = { [weak self] time, ended in self?.mobileScrub(to: time, ended: ended) }
        mobileChromeTracker.start()
        installPictureInPicture()
        if !playsDownload { airPlaySubtitles.start() }
    }

    /// AVKit can add its own views above the controls as its chrome builds; keep them on top.
    func keepMobileControlsOnTop() {
        guard mobileControls.superview === view, view.subviews.last !== mobileControls else { return }
        view.bringSubviewToFront(mobileControls)
    }

    func stopMobileControls() {
        mobileChromeTracker.stop()
        airPlaySubtitles.stop()
    }

    /// The transport-bar menus as the phone's menu buttons. On a button the top-level title would
    /// repeat the section heading under it ("Subtitles" over "Subtitles"), so it moves to the
    /// button's accessibility label.
    func setMobileMenus(_ menus: [UIMenu]) {
        mobileControls.setMenus(menus.map { menu in
            let bare = UIMenu(title: "", image: menu.image, identifier: menu.identifier, options: menu.options,
                              children: menu.children)
            bare.accessibilityLabel = menu.title
            return bare
        })
    }

    /// The Settings menu's rows beyond the speeds: Switch Source…, then Cast, Stream Info and, on a
    /// phone, the orientation (the Expo player's rotate button, plus following the device). Cast
    /// lives here rather than as its own button, which crowded AVKit's top bar on a phone.
    func mobileSettingsExtras() -> [UIMenuElement] {
        var extras: [UIMenuElement] = []
        // A download plays from this device's storage, which no TV can fetch.
        if !playsDownload {
            extras.append(UIAction(title: String(localized: "Cast…"), image: CastPresenter.castIcon(pointSize: 21)) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.openCastPicker() }
            })
        }
        extras += [
            UIAction(title: String(localized: "Stream Info"), image: UIImage(systemName: "info.circle")) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.presentStreamInfo() }
            },
        ]
        if UIDevice.current.userInterfaceIdiom == .phone {
            let current = Self.phoneOrientationChoice
            let choices = PhonePlayerOrientation.allCases.map { choice in
                UIAction(title: choice.title, image: UIImage(systemName: choice.systemImage),
                         state: choice == current ? .on : .off) { [weak self] _ in
                    self?.setPhoneOrientation(choice)
                }
            }
            let menu = UIMenu(title: String(localized: "Orientation"),
                              image: UIImage(systemName: current.systemImage), children: choices)
            menu.subtitle = current.title
            extras.append(menu)
        }
        return extras
    }

    private func setPhoneOrientation(_ choice: PhonePlayerOrientation) {
        Self.phoneOrientationChoice = choice
        log.notice("orientation: \(choice.rawValue)")
        enterPreferredOrientation()
        trackMenuState = nil
        rebuildTrackMenus()
    }

    // MARK: Software route

    /// The software route's surface came or went: this view becomes (or stops being) the transport.
    func mobileSoftwareSurfaceChanged(mounted: Bool) {
        mobileControls.setOwnsTransport(mounted)
        keepMobileControlsOnTop()
        if mounted { startThumbnails() }
    }

    /// The software route's clock tick.
    func updateMobileTransport(position: Double) {
        mobileControls.update(position: scrubTarget ?? position, duration: engine.duration,
                              paused: engine.state == .paused)
    }

    private func skip(by delta: Double) {
        let duration = engine.duration
        let base = scrubTarget ?? engine.currentTime
        let target = duration > 0 ? min(max(0, base + delta), duration) : max(0, base + delta)
        log.info("touch skip \(Int(delta))s to \(Int(target))s")
        Task { await engine.seek(to: target) }
    }

    /// The scrubber moved: the preview follows the finger; lifting it seeks there.
    private func mobileScrub(to time: Double, ended: Bool) {
        scrubTarget = time
        let index = thumbnails.index(at: time)
        previewIndex = index
        let transport = mobileControls.transport
        transport.showPreview(time: time, image: index.flatMap(thumbnails.cachedImage(at:)), hasThumbnails: index != nil)
        if let index, !ended {
            Task { [weak self] in
                guard let image = await self?.thumbnails.image(at: index), let self, previewIndex == index else { return }
                mobileControls.transport.updatePreviewImage(image)
            }
        }
        guard ended else { return }
        log.info("touch scrub to \(Int(time))s")
        Task { [weak self] in
            guard let self else { return }
            await engine.seek(to: time)
            if scrubTarget == time {
                scrubTarget = nil
                previewIndex = nil
            }
            try? await Task.sleep(for: .milliseconds(600))
            if scrubTarget == nil { mobileControls.transport.hidePreview() }
        }
    }
}
#endif
