import SwiftUI
import UIKit

/// Online subtitles in the VOD player: the automatic search once the session is up, the
/// Subtitles menu's Search Online… page, the status toast, and the online track's cues handed
/// to the overlay (both routes). The search and translation logic lives in `OnlineSubtitles`.
extension PlayerViewController {
    /// What the subtitle search and download describe the playback as. The release name is the
    /// stream's file name, which the similarity scoring compares against provider releases.
    var subtitleQuery: APIClient.SubtitleQuery {
        let file = (streamPath as NSString).lastPathComponent
        return APIClient.SubtitleQuery(
            imdbID: request.title.imdbID, title: request.title.name, year: request.title.year,
            season: request.episode?.season, episode: request.episode?.episode,
            releaseName: file.removingPercentEncoding ?? file)
    }

    func bindOnlineSubtitles() {
        subtitleStatus.install(in: view)
        onlineSubtitles.onTrack = { [weak self] track, isNew in
            guard let self, !didFinish else { return }
            if isNew {
                // Like a menu pick: it survives an audio-switch reload.
                userPickedSubtitle = true
                selectSubtitle(OnlineSubtitles.trackID, reason: "online ready")
            } else if activeSubtitle == OnlineSubtitles.trackID {
                log.info("online subtitle grew to \(track.cues.count) cues")
                subtitleOverlay.setCues(track.cues)
            }
        }
        onlineSubtitles.onSelectEmbedded = { [weak self] id in
            guard let self, !didFinish else { return }
            userPickedSubtitle = true
            selectSubtitle(id, reason: "online fallback")
        }
        onlineSubtitles.onStatus = { [weak self] text, hideAfter in
            guard let self, !didFinish else { return }
            subtitleStatus.show(text, hideAfter: hideAfter)
            if softwareSurfaceMounted { softwareHUD.flash() }
        }
        onlineSubtitles.onSettings = { [weak self] in self?.rebuildTrackMenus() }
        Task { [weak self] in _ = await self?.onlineSubtitles.loadSettings() }
    }

    /// Once the session is up and the server's pick is on screen.
    func startAutoSubtitleSearch() {
        // A subtitle picked by hand in the source list stands as chosen.
        guard !tracks.subtitlePickedByHand else { return }
        onlineSubtitles.autoSearchIfNeeded(preferences: tracks, embedded: engine.subtitleTracks,
                                           position: max(lastKnownPosition, request.startPosition ?? 0))
    }

    // MARK: Search Online… and Translate…

    /// Opens the search page over the paused player.
    func openSubtitleSearch() {
        presentSubtitlePage(event: "manual_search_open") { [weak self] in
            guard let self else { return nil }
            let model = SubtitleSearchModel(
                preferredLanguage: tracks.subtitleLanguage, releaseName: subtitleQuery.releaseName,
                search: { [weak self] language in try await self?.onlineSubtitles.search(language: language) ?? [] })
            return UIHostingController(rootView: SubtitleSearchView(
                model: model, heading: request.displayTitle,
                onPick: { [weak self] result, language in
                    self?.closeSubtitlePage { $0.onlineSubtitles.use(result, language: language) }
                },
                onClose: { [weak self] in self?.closeSubtitlePage() }))
        }
    }

    /// Opens the Translate… page (source track, then target language) over the paused player.
    func openSubtitleTranslate() {
        presentSubtitlePage(event: "manual_translate_open") { [weak self] in
            guard let self else { return nil }
            let translatable = OnlineSubtitles.translatableTracks(engine.subtitleTracks)
            let sources = translatable.map {
                SubtitleTranslateView.Source(id: $0.id, title: $0.subtitleMenuTitle, detail: $0.subtitleMenuDetail)
            }
            return UIHostingController(rootView: SubtitleTranslateView(
                heading: request.displayTitle, sources: sources,
                onPick: { [weak self] id, language in
                    self?.closeSubtitlePage { player in
                        guard let source = translatable.first(where: { $0.id == id }) else { return }
                        player.onlineSubtitles.translate(
                            source, container: OnlineSubtitles.containerTracks(player.engine.subtitleTracks),
                            to: language.code, position: player.lastKnownPosition)
                    }
                },
                onClose: { [weak self] in self?.closeSubtitlePage() }))
        }
    }

    /// Presents a subtitle page, pausing playback until it closes. Called from a menu action,
    /// so it waits for the menu (or action sheet) to finish dismissing first.
    private func presentSubtitlePage(event: String, make: @escaping () -> UIViewController?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !didFinish, subtitleSearch == nil, presentedViewController == nil,
                  let page = make() else { return }
            page.modalPresentationStyle = .overFullScreen
            page.view.backgroundColor = .clear
            let resume = engine.state == .playing
            if resume { engine.pause() }
            log.notice("[auto-sub] event=\(event) resume=\(resume)")
            subtitleSearch = (page, resume)
            present(page, animated: true)
        }
    }

    /// Closes the page, runs the pick (if any), and resumes when it was playing.
    private func closeSubtitlePage(then pick: ((PlayerViewController) -> Void)? = nil) {
        guard let page = subtitleSearch else { return }
        subtitleSearch = nil
        page.page.dismiss(animated: true)
        pick?(self)
        if page.resume, !didFinish { engine.play() }
    }
}
