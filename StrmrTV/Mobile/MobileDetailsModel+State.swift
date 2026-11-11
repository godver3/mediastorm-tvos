#if os(iOS)
import SwiftUI

/// Watched state, the prequeued stream's Audio & Subtitles, and episode orderings, as the TV
/// page's `DetailsView+WatchState`, `+Tracks` and `+Ordering`.
extension MobileDetailsModel {
    // MARK: Watched

    /// Movies: flips watched and reloads. Returns an error message on failure.
    func toggleMovieWatched() async -> String? {
        let watched = !(movieWatched == true)
        do {
            try await APIClient.shared.setWatched(watched, movie: target)
            movieWatched = watched
            await load()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The episodes flip at once; the page reloads after. Whole-show and whole-season changes
    /// carry their scope so Trakt-style providers record them with their own bulk calls.
    func markWatched(_ watched: Bool, _ episodes: [Episode], scope: WatchedScope?, titles: TitleStateStore) {
        guard !episodes.isEmpty else { return }
        let previous = episodes.map { ($0.id, watchedOverrides[$0.id]) }
        for ep in episodes { watchedOverrides[ep.id] = watched }
        Task {
            do {
                try await APIClient.shared.setWatched(watched, episodes: episodes, of: target, scope: scope)
                await load()
                await titles.seriesWatchStateChanged()
            } catch {
                for (id, value) in previous { watchedOverrides[id] = value }
                titles.show(toast: String(localized: "Failed to update watched state"))
            }
        }
    }

    /// Marks `episodes` now, or after confirmation when the change is big (`BulkWatchChange`).
    func requestMark(_ watched: Bool, _ episodes: [Episode], scope: WatchedScope?,
                     extent: BulkWatchChange.Extent, titles: TitleStateStore) {
        guard !episodes.isEmpty else { return }
        guard BulkWatchChange.needsConfirmation(extent, count: episodes.count) else {
            markWatched(watched, episodes, scope: scope, titles: titles)
            return
        }
        let change = BulkWatchChange(watched: watched, count: episodes.count, seriesName: target.name,
                                     extent: extent) { [weak self] in
            self?.markWatched(watched, episodes, scope: scope, titles: titles)
        }
        // Let the menu (or a season's context menu) finish closing before the dialog presents.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            pendingBulkWatch = change
        }
    }

    func toggleWatched(_ episode: Episode, titles: TitleStateStore) {
        markWatched(!isWatched(episode), [episode], scope: nil, titles: titles)
    }

    // MARK: Audio & Subtitles (the prequeued stream's tracks)

    /// The page's prequeue, while it resolves or once it lists tracks for the episode Play
    /// targets; nil hides the Audio & Subtitles line.
    var warmPrequeue: WarmPrequeue? {
        guard primaryVersions.isEmpty else { return nil }  // Play uses a library copy
        guard let warm = PlaybackCoordinator.shared.warm, warm.titleID == target.titleID,
              warm.profile == APIClient.shared.profileID else { return nil }
        switch warm.phase {
        case .resolving: return warm
        case .unavailable: return nil
        case .ready:
            guard let status = warm.status else { return nil }
            if !target.isMovie {
                guard let ep = activeEpisode, status.targetEpisode?.seasonNumber == ep.seasonNumber,
                      status.targetEpisode?.episodeNumber == ep.episodeNumber else { return nil }
            }
            return warm
        }
    }

    var currentPrequeueOverrides: ManualTrackOverrides {
        guard let status = warmPrequeue?.status, prequeueOverrides.streamPath == status.streamPath else {
            return ManualTrackOverrides()
        }
        return prequeueOverrides.overrides
    }

    /// The picks to hand to Play, bound to the prequeued stream.
    var prequeuePick: PrequeuePick? {
        guard let status = warmPrequeue?.status, let path = status.streamPath else { return nil }
        let overrides = currentPrequeueOverrides
        guard !overrides.isEmpty else { return nil }
        let lists = status.trackLists
        return PrequeuePick(streamPath: path, episode: status.targetEpisode,
                            pick: ManualTrackPick(overrides: overrides, audio: lists.audio, subtitles: lists.subtitles))
    }

    /// The audio and subtitle Play will use: ("English · E-AC-3", "English Subtitles").
    var tracksSummary: (audio: String, subtitles: String)? {
        guard let status = warmPrequeue?.status else { return nil }
        let lists = status.trackLists
        let defaults = status.trackDefaults
        let overrides = currentPrequeueOverrides
        var audioText = String(localized: "Default")
        let audioIndex = overrides.audioTrack ?? defaults.audio
        if let audio = lists.audio.first(where: { $0.index == audioIndex }) ?? lists.audio.first {
            let codec = TrackLabels.format(audio.codec)
            audioText = TrackLabels.language(audio.language) + (codec.isEmpty ? "" : " · \(codec)")
        }
        let subtitleIndex = overrides.subtitleTrack.map { $0 == ManualTrackOverrides.off ? nil : $0 } ?? defaults.subtitle
        let subtitleText = lists.subtitles.first(where: { $0.index == subtitleIndex })
            .map { TrackLabels.language($0.language) } ?? String(localized: "Off")
        return (audioText, subtitleText)
    }

    func showTracks() {
        guard warmPrequeue?.status != nil else { return }
        showsPrequeueTracks = true
        Task { prequeueTrackPreferences = await ManualTrackPreferences.current(content: contentPreference) }
    }

    // MARK: Episode order

    var offersOrderings: Bool { !target.isMovie && orderings.count > 1 }

    var activeOrderingEntry: SeriesOrdering? {
        orderings.first { $0.type == (pickedOrdering ?? activeOrdering) }
    }

    var activeOrderingName: String { activeOrderingEntry?.name ?? String(localized: "Default") }

    func orderingLabel(_ ordering: SeriesOrdering) -> String {
        ordering.isOfficial == true ? "\(ordering.name) (Default)" : ordering.name
    }

    /// Shows the page in `ordering` straight away and saves it for the profile.
    func pickOrdering(_ ordering: SeriesOrdering) {
        guard ordering.type != activeOrderingEntry?.type else { return }
        pickedOrdering = ordering.type
        selectedSeason = nil
        selectedEpisodeID = nil
        let tvdbID = title?.tvdbId ?? target.tvdbID.flatMap { Int($0) }
        Task {
            if let tvdbID {
                try? await APIClient.shared.setSeriesOrdering(tvdbID: tvdbID, seasonType: ordering.type)
            }
            await load()
        }
    }

    // MARK: Header text

    var metadataLine: String {
        var parts: [String] = []
        if let y = title?.year ?? target.year { parts.append(String(y)) }
        if let c = title?.certification, !c.isEmpty { parts.append(c) }
        if target.isMovie, let r = formatRuntime(title?.runtimeMinutes) { parts.append(r) }
        let regular = seasons.filter { $0.number > 0 }.count
        if regular > 0 { parts.append(regular == 1 ? String(localized: "1 Season") : String(localized: "\(regular) Seasons")) }
        if let g = title?.genres, !g.isEmpty { parts.append(g.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// The title's release badge, else (series) whether the episode Play targets has aired.
    var headerBadge: CardBadge? {
        if let title, let badge = ReleaseBadge.forTitle(title) { return badge }
        guard !target.isMovie, let ep = activeEpisode else { return nil }
        return ReleaseBadge.forEpisode(airDate: ep.airedDate).map { CardBadge(text: $0) }
    }
}
#endif
