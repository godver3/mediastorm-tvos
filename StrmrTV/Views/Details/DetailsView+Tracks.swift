import SwiftUI

extension DetailsView {
    // MARK: Audio & Subtitles (the prequeued stream's tracks)

    /// The page's prequeue, while it resolves or once it lists tracks for the episode Play
    /// targets; nil hides the button.
    var warmPrequeue: WarmPrequeue? {
        guard primaryVersions.isEmpty else { return nil }  // Play uses a library copy
        guard let warm = playback.warm, warm.titleID == target.titleID,
              warm.profile == APIClient.shared.profileID else { return nil }
        switch warm.phase {
        case .resolving: return warm
        case .unavailable: return nil
        case .ready:
            guard let status = warm.status else { return nil }
            if !target.isMovie {
                guard let ep = primaryEpisode, status.targetEpisode?.seasonNumber == ep.seasonNumber,
                      status.targetEpisode?.episodeNumber == ep.episodeNumber else { return nil }
            }
            return warm
        }
    }

    /// The picks for the stream the prequeue resolved (empty once it resolves another).
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

    /// Icon-only like the other secondary actions: a spinner while the prequeue resolves,
    /// then the tracks icon. Its caption (when focused) names the tracks Play will use.
    @ViewBuilder
    var tracksButton: some View {
        if let warm = warmPrequeue {
            Button { showTracks() } label: {
                if warm.status == nil {
                    ProgressView().accessibilityLabel("Finding a source")
                } else {
                    Label("Audio & Subtitles", systemImage: "waveform").labelStyle(.iconOnly)
                }
            }
            .focused($focus, equals: .action(.tracks))
            .overlay(alignment: .bottom) {
                if focus == .action(.tracks) {
                    Text(tracksCaption)
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(y: 44)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// "English · E-AC-3 · Subtitles Off", for the picks or else what Play would pick.
    var tracksCaption: String {
        guard let status = warmPrequeue?.status else { return String(localized: "Finding a source…") }
        let lists = status.trackLists
        let defaults = status.trackDefaults
        let overrides = currentPrequeueOverrides
        var parts: [String] = []
        let audioIndex = overrides.audioTrack ?? defaults.audio
        if let audio = lists.audio.first(where: { $0.index == audioIndex }) ?? lists.audio.first {
            parts.append(TrackLabels.language(audio.language))
            let codec = TrackLabels.format(audio.codec)
            if !codec.isEmpty { parts.append(codec) }
        }
        let subtitleIndex = overrides.subtitleTrack.map { $0 == ManualTrackOverrides.off ? nil : $0 } ?? defaults.subtitle
        if let subtitle = lists.subtitles.first(where: { $0.index == subtitleIndex }) {
            parts.append(String(localized: "\(TrackLabels.language(subtitle.language)) Subtitles"))
        } else {
            parts.append(String(localized: "Subtitles Off"))
        }
        return parts.joined(separator: " · ")
    }

    /// Presents at once (an await first let the trailer's fade take focus and drop the
    /// cover); the allowed-language filter's preferences arrive while it opens.
    func showTracks() {
        guard warmPrequeue?.status != nil else { return }
        showPrequeueTracks = true
        Task { prequeueTrackPreferences = await ManualTrackPreferences.current(content: contentPreference) }
    }

    /// The track page for the prequeued stream; Play there starts it with the picks.
    @ViewBuilder
    var prequeueTracksPage: some View {
        if let status = warmPrequeue?.status, let path = status.streamPath {
            SourceTracksView(
                releaseName: status.releaseTitle ?? target.name, tracks: status.trackLists,
                defaults: status.trackDefaults, backdropURL: title?.backdrop?.url ?? target.backdropURL,
                preferences: prequeueTrackPreferences,
                overrides: Binding(get: { currentPrequeueOverrides },
                                   set: { prequeueOverrides = (path, $0) })
            ) { _ in
                // Leave the track page, then play what the primary button plays.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if let primary = primaryTarget { play(episode: primary.episode, from: primary.start) }
                }
            }
        }
    }
}
