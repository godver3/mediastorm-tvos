import Foundation

// The details page's Audio & Subtitles button: track picks for the stream the page's prequeue
// resolved (the Expo details page's prequeue track pills, `usePlayback` `trackOverrideAudio` /
// `trackOverrideSubtitle`), shown on the source picker's track page.

/// The prequeue started as a details page opened (`PlaybackCoordinator.prewarm`), as the
/// page's Audio & Subtitles button shows it.
struct WarmPrequeue {
    enum Phase {
        case resolving
        case ready(PrequeueStatus)
        /// Failed, expired, timed out, or prequeue is off for the profile.
        case unavailable
    }

    let titleID: String
    let profile: String
    var phase: Phase

    /// The resolved status when it lists tracks to pick from.
    var status: PrequeueStatus? {
        guard case let .ready(status) = phase, status.hasTrackLists else { return nil }
        return status
    }
}

/// Tracks checked on the track page before any pick (container stream indexes).
struct TrackDefaults: Hashable {
    var audio: Int?
    /// nil = off.
    var subtitle: Int?
    /// Subtitles are on but nothing embedded matched: the player searches online.
    var searchesOnline: Bool
}

/// Picks made on details for the prequeued stream. Track numbers belong to one file, so
/// they apply only when Play resolves that same stream (and episode).
struct PrequeuePick {
    let streamPath: String
    let episode: PrequeueStatus.TargetEpisode?
    let pick: ManualTrackPick

    func applies(to status: PrequeueStatus) -> Bool {
        status.streamPath == streamPath
            && status.targetEpisode?.seasonNumber == episode?.seasonNumber
            && status.targetEpisode?.episodeNumber == episode?.episodeNumber
    }
}

extension PrequeueStatus {
    /// The release being played: the passthrough name, else the indexer result's title, else
    /// the file name, else the server's display name (often just the title).
    var releaseTitle: String? {
        let attributes = resultAttributes ?? selectedResult?.attributes
        let passthrough = passthroughName ?? (attributes?["passthrough_format"] == "true" ? attributes?["raw_name"] : nil)
        let file = streamPath?.split(separator: "/").last.map(String.init)
        return [passthrough, attributes?["raw_title"], selectedResult?.title, file, displayName]
            .lazy.compactMap { $0?.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    var hasTrackLists: Bool {
        !(audioTracks ?? []).isEmpty || !(subtitleTracks ?? []).isEmpty
    }

    /// The stream's lists as the track page takes them, by container stream number.
    var trackLists: SourceTrackProbe {
        SourceTrackProbe(
            playable: true,
            audio: (audioTracks ?? []).map {
                ProbedAudioTrack(index: $0.index, language: $0.language, codec: $0.codec,
                                 profile: $0.profile, title: $0.title)
            },
            subtitles: (subtitleTracks ?? []).map {
                ProbedSubtitleTrack(index: $0.absoluteIndex ?? $0.index, language: $0.language, codec: $0.codec,
                                    title: $0.title, forced: $0.forced ?? false, isBitmap: $0.isBitmap ?? false)
            },
            tracksLoading: false, error: nil)
    }

    /// What Play picks for this stream: Settings › Playback's device overrides over the
    /// server's selection, as `PlaybackCoordinator.play` applies them.
    @MainActor
    var playSelection: TrackSelection? {
        TrackPreferences.overridden(self)?.selection ?? trackSelection
    }

    @MainActor
    var trackDefaults: TrackDefaults {
        let selection = playSelection
        let subtitle = selection?.subtitleMode == "off" ? nil
            : (selection?.subtitle ?? selection?.textSubtitle)?.streamIndex
        let mode = selection?.subtitleMode ?? "off"
        return TrackDefaults(audio: selection?.audio?.streamIndex, subtitle: subtitle,
                             searchesOnline: subtitle == nil && mode != "off")
    }
}

extension ManualTrackPick {
    /// Playback preferences for a stream played with these picks: Settings › Playback's
    /// device overrides first (from the picked lists), then the picks over them.
    @MainActor
    func preferences(over server: TrackSelection?) -> TrackPreferences {
        let base = TrackPreferences.overridden(server, audio: audioStreams, subtitles: subtitleStreams)?.selection
            ?? server
        let selection = selection(over: base)
        var tracks = TrackPreferences(selection: selection)
        tracks.isClientPick = true
        tracks.subtitlePickedByHand = overrides.subtitleTrack != nil
        SourceTracksModel.log.notice(
            "playing with picks: audio \(overrides.audioTrack ?? -1) -> \(selection.audio?.streamIndex ?? -1), "
            + "subtitle \(overrides.subtitleTrack.map(String.init) ?? "default") -> "
            + "\(selection.subtitle?.streamIndex ?? -1) (\(selection.subtitleMode ?? "-")); server audio "
            + "\(server?.audio?.streamIndex ?? -1), subtitle \(server?.subtitle?.streamIndex ?? -1)")
        return tracks
    }
}
