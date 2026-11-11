import AetherEngine
import UIKit

/// Engine binding: state/route/track publishers, the software surface, the server audio pick.
extension PlayerViewController {
    func bindEngine() {
        engine.$videoRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in self?.setSoftwareSurface(mounted: route == .software) }
            .store(in: &cancellables)

        engine.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self else { return }
                noteProgress(time)
                updateSkipAction(at: time)
                sampleCreditsIfDue(at: time)
                prefetchNextIfNear(time)
                guard softwareSurfaceMounted else { return }
                #if os(iOS)
                updateMobileTransport(position: time)
                #else
                softwareHUD.update(position: scrubTarget ?? time, duration: engine.duration,
                                   paused: engine.state == .paused)
                #endif
            }
            .store(in: &cancellables)

        // Both routes: the overlay draws the engine's cues against the frame on screen.
        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in
                // The online track's cues are the app's own; the engine has none selected then.
                guard let self, activeSubtitle != OnlineSubtitles.trackID else { return }
                subtitleOverlay.setCues(cues)
            }
            .store(in: &cancellables)
        // The device's subtitle style (Settings, or the subtitle menu's Style picks), live.
        SubtitleStyleStore.shared.$style
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in
                guard let self else { return }
                subtitleOverlay.style = style
                if !subtitleTracks.isEmpty { rebuildTrackMenus() }
            }
            .store(in: &cancellables)
        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, subtitleOverlay.superview != nil else { return }
                subtitleOverlay.update(sourceTime: time)
            }
            .store(in: &cancellables)

        // Audio: the engine serves only the active track to AVPlayer, so AVKit's own audio
        // list has one entry. A transport-bar menu lists every track in the source.
        engine.$audioTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                self?.audioTracks = tracks
                self?.rebuildTrackMenus()
            }
            .store(in: &cancellables)
        engine.$subtitleTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                self?.subtitleTracks = tracks
                self?.rebuildTrackMenus()
            }
            .store(in: &cancellables)
        engine.$activeAudioTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                if let pending = pendingAudioPick, pending == active {
                    log.info("audio switch to stream \(pending) confirmed")
                    pendingAudioPick = nil
                    audioPickTask?.cancel()
                }
                rebuildTrackMenus()
            }
            .store(in: &cancellables)

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleStateChange(state) }
            .store(in: &cancellables)
    }

    /// The software route also gets its own HUD (and scrub previews) and the subtitle overlay
    /// above its surface; the native route's overlay goes back in AVKit's content overlay.
    func setSoftwareSurface(mounted: Bool) {
        guard mountSoftwareSurface(mounted) else { return }
        #if os(iOS)
        // The phone's touch controls are the transport there (`MobilePlayer+Controls`).
        if mounted {
            Self.fill(subtitleOverlay, in: overlayHost)
            overlayHost.insertSubview(subtitleOverlay, aboveSubview: softwareSurface)
        } else {
            subtitleOverlay.removeFromSuperview()
            if !didFinish { mountSubtitleOverlay() }
        }
        mobileSoftwareSurfaceChanged(mounted: mounted)
        #else
        if mounted {
            softwareHUD.onFocusChange = { [weak self] in
                self?.setNeedsFocusUpdate()
                self?.updateFocusIfNeeded()
            }
            Self.fill(softwareHUD, in: view)
            Self.fill(subtitleOverlay, in: overlayHost)
            overlayHost.insertSubview(subtitleOverlay, aboveSubview: softwareSurface)
            view.addSubview(softwareHUD)
            softwareHUD.flash()
            startThumbnails()
        } else {
            subtitleOverlay.removeFromSuperview()
            softwareHUD.removeFromSuperview()
            if !didFinish { mountSubtitleOverlay() }
        }
        #endif
    }

    /// The engine loaded the server's audio pick by container stream index; confirm it against
    /// the engine's track list (typeIndex, then language + languageIndex) and switch if needed.
    func applyServerAudioPick() {
        guard let id = tracks.audioTrackID(in: engine.audioTracks), id != engine.activeAudioTrackIndex else { return }
        log.info("server audio pick: switching to stream \(id)")
        engine.selectAudioTrack(index: id)
    }
}
