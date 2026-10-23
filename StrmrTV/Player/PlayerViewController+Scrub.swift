import UIKit

/// The software route has no AVKit transport bar: the remote is handled here, and seek
/// previews come from the backend's thumbnail API, drawn by the HUD while seeking.
extension PlayerViewController {
    // MARK: Software-route remote handling

    /// Returns false for presses AVKit should handle.
    func handleSoftwarePress(_ press: UIPress) -> Bool {
        switch press.type {
        case .select, .playPause:
            engine.togglePlayPause()
        case .leftArrow:
            scrub(by: -Self.scrubStep)
        case .rightArrow:
            scrub(by: Self.scrubStep)
        case .downArrow:
            // No transport bar for the Subtitles menu here: Down opens it as a sheet.
            presentSubtitlePicker()
            return true
        case .upArrow:
            // Nor for Settings › Switch Source…: Up lists the other sources.
            presentSourcePicker()
            return true
        case .menu:
            log.notice("menu pressed on the software route; closing")
            dismiss(animated: true)
            return true
        default:
            return false
        }
        softwareHUD.flash()
        return true
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
