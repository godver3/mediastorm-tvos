import UIKit

/// The software route has no AVKit transport bar: the remote is handled here, as AVKit's bar
/// handles it, and seek previews come from the backend's thumbnail API, drawn by the HUD while
/// seeking.
extension PlayerViewController {
    // MARK: Software-route remote handling

    /// Returns false for presses AVKit should handle. With the HUD's menu row focused, the focus
    /// engine moves along the row and Select opens a menu; only what leaves the row lands here.
    func handleSoftwarePress(_ press: UIPress) -> Bool {
        let hud = softwareHUD
        switch press.type {
        case .playPause:
            engine.togglePlayPause()
        case .select:
            // A focused row button or Skip capsule takes Select itself.
            guard !hud.rowFocused, !hud.isActionFocused else { return true }
            engine.togglePlayPause()
        case .leftArrow, .rightArrow:
            guard !hud.rowFocused else { return true }
            if hud.isInfoShowing { hud.setInfo(visible: false) }
            scrub(by: press.type == .leftArrow ? -Self.scrubStep : Self.scrubStep)
        case .upArrow:
            if hud.isInfoShowing {
                hud.setInfo(visible: false)
            } else if hud.isShowing, !hud.rowFocused {
                hud.focusRow()
            } else {
                hud.flash()
            }
            return true
        case .downArrow:
            if hud.rowFocused {
                hud.releaseRow()
                hud.flash()
            } else {
                hud.setInfo(visible: !hud.isInfoShowing)
            }
            return true
        case .menu:
            // UIKit's own Menu handling closes the player once nothing is open; until then the
            // base class's Menu recognizer takes the press (`closeSoftwareHUDLayer`).
            if !softwareHUDHasOpenLayer { log.notice("menu pressed on the software route; closing") }
            return true
        default:
            return false
        }
        hud.flash()
        return true
    }

    /// Whether Menu would close part of the HUD (as AVKit: what is open, then the bar) rather
    /// than the player.
    override var softwareHUDHasOpenLayer: Bool {
        let hud = softwareHUD
        return softwareSurfaceMounted && subtitleSearch == nil && presentedViewController == nil
            && (hud.isActionFocused || hud.rowFocused || hud.isInfoShowing || hud.isShowing)
    }

    override func closeSoftwareHUDLayer() {
        let hud = softwareHUD
        if hud.isActionFocused {
            dismissSkipActionIfMenu()
        } else if hud.rowFocused || hud.isInfoShowing {
            hud.releaseRow()
            hud.setInfo(visible: false)
        } else {
            hud.hide()
        }
    }

    // MARK: Scrub thumbnails

    func startThumbnails() {
        guard previewsEnabled, !thumbnailsStarted, !engine.isLive else { return }
        thumbnailsStarted = true
        thumbnails.onChange = { [weak self] in self?.refreshPreview() }
        thumbnails.start { [weak self] in
            guard let self else { return .init(duration: 0, playbackTime: 0, isBuffering: true, format: .sdr,
                                               dvProfile: nil, chapterTimes: []) }
            return .init(duration: engine.duration, playbackTime: lastKnownPosition, isBuffering: engine.isBuffering,
                         format: engine.sourceVideoFormat, dvProfile: engine.sourceDVProfile,
                         chapterTimes: engine.mediaChapters.map(\.startSeconds))
        }
    }

    /// Moves the pending seek by `delta` and shows its preview; the seek itself is sent
    /// once presses stop for a moment.
    private func scrub(by delta: Double) {
        let duration = engine.duration
        guard duration > 0 else {
            Task { await engine.seek(to: max(0, engine.currentTime + delta)) }
            return
        }
        let target = min(max(0, (scrubTarget ?? engine.currentTime) + delta), duration)
        scrubTarget = target
        softwareHUD.update(position: target, duration: duration, paused: engine.state == .paused)
        showPreview(at: target)

        scrubCommit?.cancel()
        let commit = DispatchWorkItem { [weak self] in
            guard let self, let target = scrubTarget else { return }
            Task {
                await self.engine.seek(to: target)
                self.scrubTarget = nil
                self.previewIndex = nil
                try? await Task.sleep(for: .seconds(1))
                if self.scrubTarget == nil { self.softwareHUD.hidePreview() }
            }
        }
        scrubCommit = commit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: commit)
    }

    private func showPreview(at time: Double) {
        let index = thumbnails.index(at: time)
        previewIndex = index
        softwareHUD.showPreview(time: time, duration: engine.duration,
                                image: index.flatMap(thumbnails.cachedImage(at:)),
                                hasThumbnails: index != nil)
        guard let index else { return }
        Task { [weak self] in
            guard let image = await self?.thumbnails.image(at: index),
                  let self, self.previewIndex == index else { return }
            self.softwareHUD.updatePreviewImage(image)
        }
    }

    /// Thumbnails arrived while a preview is up: show the frame for it.
    private func refreshPreview() {
        guard let scrubTarget else { return }
        showPreview(at: scrubTarget)
    }
}
