import AetherEngine
import UIKit

/// Switch Source: the other ranked sources for this title / episode, from the
/// transport bar's Settings menu (hardware route) or Up (software route), as a wide full-screen
/// list (`SourceSwitchView`, the details page's source rows). The sources are searched when it is first opened (as the Expo player refreshes its
/// candidates on demand). Choosing one stops this stream and plays that source from the current
/// position with the same audio and subtitle languages; Back closes the list without changing
/// anything. No automatic migration.
extension PlayerViewController {
    /// The Settings menu's Switch Source… row.
    func switchSourceAction() -> UIAction {
        NativeChrome.switchSourceAction { [weak self] in self?.presentSourcePicker() }
    }

    func presentSourcePicker() {
        guard presentedViewController == nil, !engine.isLive, !didFinish else { return }
        if softwareSurfaceMounted { softwareHUD.flash() }
        log.notice("switch source: list opened (route \(self.engine.videoRoute.rawValue))")
        if sourceList?.results.isEmpty ?? true { subtitleStatus.show(String(localized: "Finding sources…"), hideAfter: nil) }
        Task { [weak self] in
            guard let self else { return }
            let rows: [SourceSwitchView.Row]
            do { rows = try await sourceRows() } catch {
                log.error("switch source: search failed: \(error.localizedDescription)")
                subtitleStatus.show(String(localized: "Couldn't load sources"), hideAfter: 4)
                return
            }
            subtitleStatus.hide()
            guard !didFinish, presentedViewController == nil else { return }
            present(NativeChrome.sourcePage(heading: request.displayTitle, rows: rows,
                                            onPick: { [weak self] option in self?.choose(option) },
                                            onCancel: { [weak self] in self?.log.notice("switch source: closed without a change") }),
                    animated: true)
        }
    }

    // MARK: Switching

    private func sourceRows() async throws -> [SourceSwitchView.Row] {
        let list = sourceList ?? SourceSwitchList(request: request)
        sourceList = list
        let results = try await list.load()
        let options = SourceSwitch.options(results, health: list.health, current: currentSource)
        log.notice("switch source: \(results.count) sources, current \(options.firstIndex(where: \.isCurrent).map(String.init) ?? "-")"
                   + " (\(self.currentSource.releaseName ?? self.currentSource.guid ?? self.currentSource.streamPath ?? "?"))")
        return SourceSwitchView.Row.rows(options, results: results, health: list.health)
    }

    private func choose(_ option: SourceSwitch.Option) {
        guard !option.isCurrent, let index = option.resultIndex,
              let result = sourceList?.results.first(where: { $0.index == index }) else { return }
        switchSource(to: result)
    }

    /// Stops this stream and plays `result` from the current position, carrying the languages.
    private func switchSource(to result: SourceResult) {
        guard !didFinish, !isAdvancing else { return }
        isAdvancing = true
        let position = lastKnownPosition
        let carry = currentTrackCarry()
        log.notice("switch source: \(currentSource.releaseName ?? currentSource.streamPath ?? "?") -> \(SourceSwitch.releaseName(result)) "
                   + "(\(result.serviceType)) at \(Int(position))s, carrying audio \(carry.audioLanguage ?? "-"), subtitle \(carry.subtitle)")
        let next = PlaybackRequest(title: request.title, episode: request.episode,
                                   start: position > 0 ? .seconds(position) : nil,
                                   following: request.following, artwork: request.artwork)
        dismiss(animated: true) { PlaybackCoordinator.shared.play(next, source: result, carry: carry) }
    }

    /// The active audio language and subtitle (Off, or an embedded track's language).
    private func currentTrackCarry() -> TrackCarry {
        let audio = engine.audioTracks.first { $0.id == engine.activeAudioTrackIndex }?.language
        let subtitle: TrackCarry.Subtitle
        if let active = activeSubtitle {
            subtitle = engine.subtitleTracks.first { $0.id == active }?.language
                .map { .language($0, forced: engine.subtitleTracks.first { $0.id == active }?.isForced ?? false) } ?? .unchanged
        } else {
            subtitle = .off
        }
        return TrackCarry(audioLanguage: audio, subtitle: subtitle)
    }

    /// After a switch: picks the carried languages from the new source's tracks. True when it
    /// chose the audio (the server's pick is then not re-applied).
    func applyTrackCarry() -> Bool {
        guard let carry = trackCarry else { return false }
        let audioTracks = engine.audioTracks.filter { !$0.isExternal }.map(TrackCarry.Track.init)
        let subtitleTracks = OnlineSubtitles.containerTracks(engine.subtitleTracks).map(TrackCarry.Track.init)
        if let pick = carry.subtitleTrackID(in: subtitleTracks) {
            userPickedSubtitle = true
            activeSubtitle = pick
            tracks.subtitlePickedByHand = true
        }
        let audio = carry.audioTrackID(in: audioTracks)
        log.notice("switch source: carried audio \(carry.audioLanguage ?? "-") -> \(audio ?? -1), "
                   + "subtitle \(carry.subtitle) -> \(userPickedSubtitle ? String(activeSubtitle ?? -1) : "source pick")")
        guard let audio else { return false }
        if audio != engine.activeAudioTrackIndex { engine.selectAudioTrack(index: audio) }
        return true
    }
}

extension TrackCarry.Track {
    init(_ track: TrackInfo) {
        self.init(id: track.id, language: track.language, isForced: track.isForced, isCommentary: track.isCommentary)
    }
}
