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
    ///
    /// Startup publishes track lists, the active audio track, the server and subtitle picks in
    /// a burst, and every `transportBarCustomMenuItems` assignment makes AVKit reload the
    /// button row (recycling its cells, with AVKit's own Audio button coming and going as the
    /// audio list fills), which showed as the buttons reshuffling until they settled. So the
    /// menus stay back until the load's picks are in, a burst coalesces into one rebuild on
    /// the next run-loop pass, and a rebuild that would change nothing is skipped.
    func rebuildTrackMenus() {
        guard trackMenusReady else {
            // AVKit's own buttons stay hidden too, so the row fills in once, complete. (A phone's
            // AVKit chrome has no such row; its menus are the phone's own buttons.)
            #if !os(iOS)
            settingsHider.start(on: view, hiding: [TransportSettingsHider.legible, TransportSettingsHider.audible])
            #endif
            return
        }
        guard !trackMenuRebuildQueued else { return }
        trackMenuRebuildQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            trackMenuRebuildQueued = false
            // A rebuild queued as the player closes would restart the hider it stopped.
            guard !didFinish else { return }
            applyTrackMenus()
        }
    }

    private func applyTrackMenus() {
        let selected = pendingAudioPick ?? engine.activeAudioTrackIndex
        let state = TrackMenuState(
            audio: audioTracks.map {
                TrackMenuItem(id: $0.id, title: $0.audioMenuTitle, detail: $0.audioMenuDetail, isSelected: $0.id == selected)
            },
            subtitles: subtitleMenuItems, subtitlesOff: activeSubtitle == nil, style: SubtitleStyleStore.shared.style,
            canSearch: onlineSubtitles.searchAvailable, canTranslate: onlineSubtitles.translateAvailable,
            speeds: engine.isLive ? nil : Self.speedChoices.filter { $0 <= engine.maxSupportedRate },
            speed: playbackSpeed)
        guard state != trackMenuState else { return }
        trackMenuState = state

        var menus: [UIMenu] = []
        // Always audio, subtitles, settings (AVKit's own Audio button, shown for a single
        // track, is moved to the front by the hider).
        if state.audio.count > 1 {
            menus.append(NativeChrome.audioMenu(state.audio) { [weak self] id in self?.selectAudio(id) })
        }
        var onSearch: (@MainActor () -> Void)?
        if state.canSearch { onSearch = { [weak self] in self?.openSubtitleSearch() } }
        var onTranslate: (@MainActor () -> Void)?
        if state.canTranslate { onTranslate = { [weak self] in self?.openSubtitleTranslate() } }
        if !state.subtitles.isEmpty || state.canSearch {
            menus.append(NativeChrome.subtitleMenu(
                state.subtitles, offSelected: state.subtitlesOff, style: state.style,
                onSelect: { [weak self] id in
                    self?.userPickedSubtitle = true
                    self?.selectSubtitle(id, reason: "menu pick")
                },
                onStyle: { style in SubtitleStyleStore.shared.style = style },
                onSearch: onSearch, onTranslate: onTranslate))
        }
        if let speeds = state.speeds {
            menus.append(NativeChrome.settingsMenu(speeds: speeds, current: state.speed,
                                                   extra: settingsMenuExtras(), speedSubmenu: Self.speedSubmenu) { [weak self] speed in
                self?.selectSpeed(speed)
            })
        }
        transportBarCustomMenuItems = menus
        softwareHUD.setMenus(menus)
        #if os(iOS)
        setMobileMenus(menus)
        #endif
        #if !os(iOS)
        // AVKit's Subtitles button would offer the legible group, which these sessions don't use.
        var hidden: Set<String> = [TransportSettingsHider.legible]
        if state.audio.count > 1 { hidden.insert(TransportSettingsHider.audible) }
        settingsHider.start(on: view, hiding: hidden)
        #endif
    }

    /// A phone's Settings menu has the speeds as a submenu (`NativeChrome.settingsMenu`).
    private static var speedSubmenu: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// The Settings menu's rows after the speeds: Switch Source… (and the phone's own rows).
    private func settingsMenuExtras() -> [UIMenuElement] {
        #if os(iOS)
        // A downloaded file is the one copy on the device: nothing to switch to.
        return (playsDownload ? [] : [switchSourceAction()]) + mobileSettingsExtras()
        #else
        return [switchSourceAction()]
        #endif
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

/// Everything the transport-bar menus show; equal states build identical menus.
struct TrackMenuState: Equatable {
    let audio: [TrackMenuItem]
    let subtitles: [TrackMenuItem]
    let subtitlesOff: Bool
    let style: SubtitleStyle
    let canSearch: Bool
    let canTranslate: Bool
    /// Nil on live, which has no settings menu.
    let speeds: [Float]?
    let speed: Float
}
