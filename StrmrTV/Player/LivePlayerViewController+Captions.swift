import AetherEngine
import UIKit

/// Captions: whatever subtitle tracks the engine finds (in-band CEA-608, DVB / teletext
/// streams, a WebVTT rendition, or the legible options AVPlayer reports for an HLS session)
/// plus, for an HLS session, the server's own EIA-608 extraction (`ServerLiveCaptions`),
/// in a Subtitles menu in the transport bar (on the software route, Select opens it).
extension LivePlayerViewController {
    /// The overlay above the video: over the software surface on that route, else in AVKit's
    /// content overlay (AVPlayer draws the legible options of an HLS session itself).
    func mountSubtitleOverlay() {
        let host = overlayHost
        Self.fill(subtitleOverlay, in: host)
        if softwareSurfaceMounted {
            host.insertSubview(subtitleOverlay, aboveSubview: softwareSurface)
        } else if subtitleOverlay.superview !== host {
            host.addSubview(subtitleOverlay)
        }
    }

    /// The menu's entries: the engine's tracks, then the server's captions when the engine
    /// has none of its own.
    var subtitleChoices: [TrackMenuItem] {
        var items = subtitleTracks.map {
            TrackMenuItem(id: $0.id, title: $0.subtitleMenuTitle, detail: $0.subtitleMenuDetail,
                          isSelected: $0.id == activeSubtitle)
        }
        if serverCaptions?.isAvailable == true, !subtitleTracks.contains(where: Self.isClosedCaption) {
            items.append(TrackMenuItem(id: Self.serverCaptionsID, title: String(localized: "Closed Captions"),
                                       detail: "CC", isSelected: activeSubtitle == Self.serverCaptionsID))
        }
        return items
    }

    private static func isClosedCaption(_ track: TrackInfo) -> Bool {
        let codec = track.codec.lowercased()
        if ["eia_608", "eia_708", "cea708", "cea_708"].contains(codec) { return true }
        // AVPlayer's legible options for an HLS session come through as WebVTT by name.
        let name = track.name.lowercased()
        return name.contains("closed caption") || name.hasSuffix(" cc") || name == "cc"
    }

    func rebuildSubtitleMenu() {
        let items = subtitleChoices
        let addScreen = UIAction(title: String(localized: "Add Screen"), image: UIImage(systemName: "rectangle.split.2x2")) {
            [weak self] _ in self?.addScreen()
        }
        transportBarCustomMenuItems = [addScreen] + (items.isEmpty ? [] : [
            NativeChrome.subtitleMenu(
                items, offSelected: activeSubtitle == nil, style: SubtitleStyleStore.shared.style,
                onSelect: { [weak self] id in self?.pickSubtitle(id) },
                onStyle: { [weak self] style in
                    SubtitleStyleStore.shared.style = style
                    self?.rebuildSubtitleMenu()
                }),
        ])
        // AVKit's own Subtitles button would offer AVPlayer's legible group a second time.
        settingsHider.start(on: view, hiding: [TransportSettingsHider.legible])
    }

    private func pickSubtitle(_ id: Int?) {
        pickedSubtitle = id
        captionsWanted = id != nil
        LiveCaptionPreference.isOn = id != nil
        selectSubtitle(id, reason: "menu pick")
    }

    /// With captions wanted and none showing: the menu's pick when it is offered again, else
    /// closed captions, else a track in the device's language, else the first track.
    func applyCaptionPick() {
        guard captionsWanted, activeSubtitle == nil, !didFinish else { return }
        let ids = subtitleChoices.map(\.id)
        guard !ids.isEmpty else { return }
        let languages = TrackPreferences.deviceLanguages
        let id = pickedSubtitle.flatMap { ids.contains($0) ? $0 : nil }
            ?? subtitleTracks.first(where: Self.isClosedCaption)?.id
            ?? (ids.contains(Self.serverCaptionsID) ? Self.serverCaptionsID : nil)
            ?? subtitleTracks.first { track in
                languages.contains { TrackPreferences.sameLanguage(track.language, $0) }
            }?.id
            ?? ids[0]
        selectSubtitle(id, reason: "captions on")
    }

    private func selectSubtitle(_ id: Int?, reason: String) {
        let wasServer = activeSubtitle == Self.serverCaptionsID
        activeSubtitle = id
        if wasServer, id != Self.serverCaptionsID {
            serverCaptions?.stop()
            serverCaptionClock?.invalidate()
            serverCaptionClock = nil
        }
        switch id {
        case nil:
            log.notice("subtitle \(reason): off")
            engine.clearSubtitle()
        case Self.serverCaptionsID:
            log.notice("subtitle \(reason): server captions")
            engine.clearSubtitle()
            subtitleOverlay.setCues([])
            serverCaptions?.start()
            startServerCaptionClock()
        case let id?:
            let codec = subtitleTracks.first { $0.id == id }?.codec ?? "?"
            log.notice("subtitle \(reason): stream \(id) \(codec) (route \(self.engine.videoRoute.rawValue))")
            engine.selectSubtitleTrack(index: id)
        }
        mountSubtitleOverlay()
        rebuildSubtitleMenu()
    }

    func startServerCaptions() {
        stopServerCaptions()
        guard let sessionID else { return }
        let captions = ServerLiveCaptions(sessionID: sessionID)
        captions.onAvailable = { [weak self] in
            self?.applyCaptionPick()
            self?.rebuildSubtitleMenu()
        }
        captions.onCues = { [weak self] cues in
            guard let self, activeSubtitle == Self.serverCaptionsID else { return }
            subtitleOverlay.setCues(cues)
        }
        serverCaptions = captions
        captions.detect()
    }

    func stopServerCaptions() {
        serverCaptions?.cancel()
        serverCaptions = nil
        serverCaptionClock?.invalidate()
        serverCaptionClock = nil
        if activeSubtitle == Self.serverCaptionsID {
            activeSubtitle = nil
            subtitleOverlay.setCues([])
        }
    }

    /// The server's SRT is timed on the session's playlist, which is AVPlayer's own timeline
    /// for the HLS session, so it is drawn against the player's clock.
    private func startServerCaptionClock() {
        serverCaptionClock?.invalidate()
        serverCaptionClock = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let time = self.player?.currentTime().seconds, time.isFinite else { return }
                self.subtitleOverlay.update(sourceTime: time)
            }
        }
    }

    /// The Subtitles menu as an action sheet, for the software route.
    func presentSubtitlePicker() {
        let sheet = UIAlertController(title: String(localized: "Subtitles"), message: nil, preferredStyle: .actionSheet)
        let off = UIAlertAction(title: (activeSubtitle == nil ? "✓ " : "") + String(localized: "Off"), style: .default) {
            [weak self] _ in self?.pickSubtitle(nil)
        }
        sheet.addAction(off)
        for item in subtitleChoices {
            let title = (item.isSelected ? "✓ " : "") + [item.title, item.detail].compactMap { $0 }.joined(separator: " · ")
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in self?.pickSubtitle(item.id) })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        present(sheet, animated: true)
    }
}
