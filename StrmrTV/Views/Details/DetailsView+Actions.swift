import SwiftUI

extension DetailsView {
    // MARK: Actions

    /// The episode / resume point the primary button plays, and its label.
    var primaryTarget: (episode: Episode?, start: StartPoint?, label: String)? {
        if target.isMovie {
            if let resumeAt = resumePoint(nil) { return (nil, resumeAt, String(localized: "Resume from \(resumeAt.label)")) }
            return (nil, nil, String(localized: "Play"))
        }
        guard let ep = primaryEpisode else { return nil }
        if let resumeAt = resumePoint(ep) { return (ep, resumeAt, String(localized: "Resume \(ep.code) · \(resumeAt.label)")) }
        return (ep, nil, String(localized: "Play \(ep.code)"))
    }

    // One primary Button whose label changes as details load (Play → Resume), rather than
    // swapping buttons: replacing the focused view drops focus off the page.
    var actionButtons: some View {
        HStack(spacing: 30) {
            Button {
                if let primary = primaryTarget { play(episode: primary.episode, from: primary.start) }
            } label: {
                Label(primaryTarget?.label ?? String(localized: "Play"), systemImage: "play.fill")
            }
            .focused($focus, equals: .action(.primary))

            if let primary = primaryTarget, primary.start != nil {
                Button { play(episode: primary.episode, from: nil) } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                }
                .focused($focus, equals: .action(.startOver))
            }
            versionsButton
            // Secondary actions are icon-only, as on the Expo details page; the labels stay
            // for VoiceOver and the focus engine.
            Button { sourcePicker = SourcePickerTarget(episode: target.isMovie ? nil : primaryEpisode) } label: {
                Label("Choose Source", systemImage: "magnifyingglass").labelStyle(.iconOnly)
            }
            .focused($focus, equals: .action(.chooseSource))
            .disabled(!target.isMovie && primaryEpisode == nil)

            tracksButton

            if trailer.available {
                Button { trailer.buttonPressed() } label: {
                    if trailer.preparingFullScreen {
                        ProgressView()
                    } else {
                        Label(trailer.showing && !trailer.paused ? "Pause Trailer" : "Play Trailer",
                              systemImage: trailer.showing && !trailer.paused ? "pause.fill" : "film")
                            .labelStyle(.iconOnly)
                    }
                }
                .focused($focus, equals: .action(.trailer))
            }

            watchlistButton
            Button { customLists.picking = target } label: {
                Label("Add to List", systemImage: "text.badge.plus").labelStyle(.iconOnly)
            }
            .focused($focus, equals: .action(.lists))
            watchedButton
            moreMenu
        }
    }

    // MARK: Watched

    func isWatched(_ episode: Episode) -> Bool {
        watchedOverrides[episode.id] ?? (episode.watched == true)
    }

    /// Series: none / some / all aired regular-season episodes watched (the Expo rule).
    var seriesWatchState: WatchStateEye.State {
        let watched = airedRegularEpisodes.reduce(0) { $0 + (isWatched($1) ? 1 : 0) }
        if watched == 0 { return .none }
        return watched == airedRegularEpisodes.count ? .complete : .partial
    }

    /// Movies: one toggle whose icon flips (focus stays on it). Series: opens the bulk
    /// watch-state screen, as the Expo app's watch-state button does.
    @ViewBuilder
    var watchedButton: some View {
        if target.isMovie {
            let watched = movieWatched == true
            Button {
                Task { await toggleMovieWatched() }
            } label: {
                Label { Text(watched ? String(localized: "Watched") : String(localized: "Mark as Watched")) }
                    icon: { WatchStateEye(state: watched ? .complete : .none) }
                    .labelStyle(.iconOnly)
            }
            .focused($focus, equals: .action(.watched))
            .accessibilityHint(watched ? "Marks this movie as not watched" : "Marks this movie as watched")
        } else if !seasons.isEmpty {
            Button { showWatchState = true } label: {
                Label { Text("Watch State") } icon: { WatchStateEye(state: seriesWatchState) }
                    .labelStyle(.iconOnly)
            }
            .focused($focus, equals: .action(.watched))
        }
    }

    func toggleMovieWatched() async {
        guard !watchedBusy else { return }
        watchedBusy = true
        defer { watchedBusy = false }
        let watched = !(movieWatched == true)
        do {
            try await APIClient.shared.setWatched(watched, movie: target)
            movieWatched = watched
            watchedError = nil
            await load()
        } catch {
            watchedError = error.localizedDescription
        }
    }

    /// Long-press toggle on one episode; the card flips at once and the page reloads after.
    func toggleWatched(_ episode: Episode) {
        let watched = !isWatched(episode)
        watchedOverrides[episode.id] = watched
        Task {
            do {
                try await APIClient.shared.setWatched(watched, episodes: [episode], of: target)
                watchedError = nil
                await load()
            } catch {
                watchedOverrides[episode.id] = nil
                watchedError = error.localizedDescription
            }
        }
    }

    var inWatchlist: Bool { watchlist.contains(target, server: serverInWatchlist) }

    // One button whose label flips, like the primary action, so focus stays on it.
    var watchlistButton: some View {
        Button {
            Task { await toggleWatchlist() }
        } label: {
            Label(inWatchlist ? String(localized: "In Watchlist") : String(localized: "Add to Watchlist"),
                  systemImage: inWatchlist ? "plus.circle.fill" : "plus")
                .labelStyle(.iconOnly)
        }
        .focused($focus, equals: .action(.watchlist))
        .accessibilityHint(inWatchlist ? "Removes this title from your watchlist" : "Adds this title to your watchlist")
    }

    /// Repeat presses while a change is in flight are ignored (disabling the focused
    /// button would drop focus off the page).
    func toggleWatchlist() async {
        guard !watchlistBusy else { return }
        watchlistBusy = true
        defer { watchlistBusy = false }
        do {
            if inWatchlist { try await watchlist.remove(target) } else { try await watchlist.add(target) }
            watchlistError = nil
        } catch {
            watchlistError = error.localizedDescription
        }
    }

    /// A Top Shelf play link opened this page: run the primary action (Resume / Play
    /// next episode) once details have loaded.
    func autoplayIfRequested() {
        guard title != nil, let primary = primaryTarget,
              DeepLinkRouter.shared.consumeAutoplay(target.titleID) else { return }
        play(episode: primary.episode, from: primary.start)
    }

    func play(episode: Episode?, from start: StartPoint?) {
        playPreferringLibrary(episode, from: start)
    }

    func request(_ episode: Episode?, from start: StartPoint?) -> PlaybackRequest {
        PlaybackRequest(title: target, episode: episode.map(episodeInfo), start: start,
                        following: episode.map(airedEpisodes(after:)) ?? [],
                        artwork: .init(
                            backdropURLs: PlaybackRequest.Artwork.rotation(
                                still: episode?.image?.url,
                                primary: title?.backdrop?.url ?? target.backdropURL,
                                alternates: title?.backdrops?.map(\.url) ?? [],
                                showing: title?.backdrop?.url ?? target.backdropURL,
                                seed: artSeed),
                            logoURL: title?.logo?.url),
                        library: libraryVersions)
    }

    func episodeInfo(_ ep: Episode) -> PlaybackRequest.EpisodeInfo {
        PlaybackRequest.EpisodeInfo(season: ep.seasonNumber, episode: ep.episodeNumber,
                                    absolute: ep.absoluteEpisodeNumber, name: ep.name, itemID: ep.itemId,
                                    imageURL: ep.image?.url, overview: ep.overview)
    }

    /// Regular-season episodes after `episode` that have aired, for Next Episode at the credits.
    func airedEpisodes(after episode: Episode) -> [PlaybackRequest.EpisodeInfo] {
        let regular = seasons.filter { $0.number > 0 }.sorted { $0.number < $1.number }.flatMap(\.episodes)
        guard let index = regular.firstIndex(where: { $0.id == episode.id }) else { return [] }
        return regular[(index + 1)...]
            .prefix { ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
            .map(episodeInfo)
    }
}
