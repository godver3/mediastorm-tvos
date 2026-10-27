import AetherEngine
import UIKit

/// Subtitles, and the transport bar's Subtitles / Audio / Settings (speed) menus.
extension PlayerViewController {
    // MARK: Subtitles

    /// Turns on the profile's subtitle (or the menu's last pick) once the session is up.
    ///
    /// Every track, text or bitmap, is selected with `selectSubtitleTrack(index:)` and drawn by
    /// `SubtitleOverlayView` on both routes; AVKit's legible group is not used. The online
    /// track's cues are the app's own (`OnlineSubtitles`), handed to the same overlay.
    func applySubtitlePick() async {
        mountSubtitleOverlay()
        let id = userPickedSubtitle
            ? activeSubtitle
            : (tracks.subtitlesExplicitlyOff ? nil : tracks.subtitleTrackID(in: engine.subtitleTracks))
        selectSubtitle(id, reason: userPickedSubtitle ? "menu pick" : "server pick")
    }

    /// Settings › Playback overrides when they couldn't be applied before the load (a manual
    /// source carries no track lists): picked from the engine's tracks, and the audio pick
    /// then switches in place like a menu pick.
    func applyDeviceTrackOverrides() {
        let audio = engine.audioTracks.filter { !$0.isExternal }.map(ClientTrackSelector.Stream.init)
        let subtitles = OnlineSubtitles.containerTracks(engine.subtitleTracks).map(ClientTrackSelector.Stream.init)
        // A library file has no server pick at all: the profile's languages choose here.
        if tracks.pickOnDevice {
            tracks = TrackPreferences.devicePick(audio: audio, subtitles: subtitles)
            return
        }
        guard !tracks.isClientPick,
              let picked = TrackPreferences.overridden(tracks.selection, audio: audio, subtitles: subtitles)
        else { return }
        tracks = picked
    }

    func selectSubtitle(_ id: Int?, reason: String) {
        let wasOnline = activeSubtitle == OnlineSubtitles.trackID
        if id == OnlineSubtitles.trackID, let online = onlineSubtitles.track {
            log.notice("subtitle \(reason): \(online.title) (\(online.detail), \(online.cues.count) cues)")
            // Set first: the engine's empty cue list after the clear must not replace these.
            activeSubtitle = id
            engine.clearSubtitle()
            subtitleOverlay.setCues(online.cues)
            rebuildTrackMenus()
            return
        }
        // An online pick with no online track left is Off.
        let next = id == OnlineSubtitles.trackID ? nil : id
        activeSubtitle = next
        if wasOnline { subtitleOverlay.setCues([]) }
        if let next {
            let codec = engine.subtitleTracks.first { $0.id == next }?.codec ?? "?"
            log.notice("subtitle \(reason): stream \(next) \(codec) (route \(self.engine.videoRoute.rawValue))")
            engine.selectSubtitleTrack(index: next)
        } else {
            log.notice("subtitle \(reason): off")
            engine.clearSubtitle()
        }
        rebuildTrackMenus()
    }

    /// The overlay over the video on the native route (the software route mounts its own,
    /// above its own surface).
    func mountSubtitleOverlay() {
        guard !softwareSurfaceMounted, subtitleOverlay.superview == nil else { return }
        Self.fill(subtitleOverlay, in: overlayHost)
        overlayHost.addSubview(subtitleOverlay)
    }

    // MARK: Track menus

    /// Replaces AVKit's Audio button (which can only list the one track the engine serves
    /// AVPlayer) and Subtitles button (the engine's native renditions are off) with identically
    /// styled menus listing every track in the source. The audio checkmark follows the pick
    /// immediately and the engine's active track once it lands.
    func rebuildTrackMenus(active: Int? = nil) {
        let selected = pendingAudioPick ?? active ?? engine.activeAudioTrackIndex
        let audioItems = audioTracks.map {
            TrackMenuItem(id: $0.id, title: $0.audioMenuTitle, detail: $0.audioMenuDetail, isSelected: $0.id == selected)
        }
        let subtitleItems = subtitleMenuItems
        var menus: [UIMenu] = []
        // Always audio, subtitles, settings (AVKit's own Audio button, shown for a single
        // track, is moved to the front by the hider).
        if audioItems.count > 1 {
            menus.append(NativeChrome.audioMenu(audioItems) { [weak self] id in self?.selectAudio(id) })
        }
        let canSearch = onlineSubtitles.searchAvailable
        var onSearch: (@MainActor () -> Void)?
        if canSearch { onSearch = { [weak self] in self?.openSubtitleSearch() } }
        var onTranslate: (@MainActor () -> Void)?
        if onlineSubtitles.translateAvailable { onTranslate = { [weak self] in self?.openSubtitleTranslate() } }
        if !subtitleItems.isEmpty || canSearch {
            menus.append(NativeChrome.subtitleMenu(
                subtitleItems, offSelected: activeSubtitle == nil, style: SubtitleStyleStore.shared.style,
                onSelect: { [weak self] id in
                    self?.userPickedSubtitle = true
                    self?.selectSubtitle(id, reason: "menu pick")
                },
                onStyle: { style in SubtitleStyleStore.shared.style = style },
                onSearch: onSearch, onTranslate: onTranslate))
        }
        if !engine.isLive {
            let speeds = Self.speedChoices.filter { $0 <= engine.maxSupportedRate }
            menus.append(NativeChrome.settingsMenu(speeds: speeds, current: playbackSpeed,
                                                   extra: [switchSourceAction()]) { [weak self] speed in
                self?.selectSpeed(speed)
            })
        }
        transportBarCustomMenuItems = menus
        softwareHUD.setMenus(menus)
        // AVKit's Subtitles button would offer the legible group, which these sessions don't use.
        var hidden: Set<String> = [TransportSettingsHider.legible]
        if audioItems.count > 1 { hidden.insert(TransportSettingsHider.audible) }
        settingsHider.start(on: view, hiding: hidden)
    }

    /// The subtitle menu's tracks: the source's, then the online one when there is one.
    var subtitleMenuItems: [TrackMenuItem] {
        var items = subtitleTracks.map {
            TrackMenuItem(id: $0.id, title: $0.subtitleMenuTitle, detail: $0.subtitleMenuDetail,
                          isSelected: $0.id == activeSubtitle)
        }
        if let online = onlineSubtitles.track {
            items.append(TrackMenuItem(id: OnlineSubtitles.trackID, title: online.title, detail: online.detail,
                                       isSelected: activeSubtitle == OnlineSubtitles.trackID))
        }
        return items
    }

    private func selectSpeed(_ speed: Float) {
        log.notice("speed menu pick: \(speed)x (route \(self.engine.videoRoute.rawValue))")
        playbackSpeed = speed
        engine.setRate(speed)
        rebuildTrackMenus()
    }

    /// Switches the audio track mid-playback. `selectAudioTrack` rebuilds the session at the
    /// current position with the new stream muxed in; if the engine has not confirmed the
    /// switch once it settles, the session is reloaded naming the stream explicitly (the
    /// engine's documented fallback for sources that cannot switch in place).
    private func selectAudio(_ id: Int) {
        guard id != engine.activeAudioTrackIndex || pendingAudioPick != nil else { return }
        log.notice("audio menu pick: stream \(id) (active \(self.engine.activeAudioTrackIndex ?? -1), route \(self.engine.videoRoute.rawValue))")
        pendingAudioPick = id
        rebuildTrackMenus()
        engine.selectAudioTrack(index: id)
        audioPickTask?.cancel()
        audioPickTask = Task { [weak self] in
            // Give the in-place rebuild time to reopen the source and land.
            try? await Task.sleep(for: .seconds(8))
            for _ in 0..<40 {
                guard let self, !Task.isCancelled, !self.didFinish, self.pendingAudioPick == id else { return }
                if self.engine.state != .loading && self.engine.state != .seeking { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard let self, !Task.isCancelled, !self.didFinish, self.pendingAudioPick == id,
                  self.engine.activeAudioTrackIndex != id else { return }
            await self.reloadWithAudio(id)
        }
    }

    private func reloadWithAudio(_ id: Int) async {
        let position = lastKnownPosition
        let wasPaused = engine.state == .paused
        log.error("audio switch to stream \(id) not confirmed (active \(self.engine.activeAudioTrackIndex ?? -1)); reloading at \(position)s")
        do {
            _ = try await engine.load(url: url, startPosition: position > 0 ? position : nil,
                                      options: makeLoadOptions(), audioSourceStreamIndex: Int32(id))
            if wasPaused { engine.pause() } else { engine.play() }
            pendingAudioPick = nil
            rebuildTrackMenus()
            await applySubtitlePick()
        } catch is CancellationError {
            return
        } catch {
            fail("Couldn't switch audio: \(error.localizedDescription)")
        }
    }
}
