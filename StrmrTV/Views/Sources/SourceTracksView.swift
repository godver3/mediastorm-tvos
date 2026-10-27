import SwiftUI

/// A source's audio and subtitle tracks, opened by a long press in the source picker (the
/// Expo TV manual picker's track modal): the profile's defaults are checked, Select on a row
/// changes the pick, Play starts this source with the picks. Menu returns to the list; the
/// picks stay with the source for the rest of the visit.
struct SourceTracksView: View {
    @StateObject private var model: SourceTracksModel
    let backdropURL: String?
    let preferences: ManualTrackPreferences
    /// Checked before any pick, in place of the defaults worked out from `preferences`.
    let defaults: TrackDefaults?
    @Binding var overrides: ManualTrackOverrides
    let onPlay: (ManualTrackPick?) -> Void

    init(result: SourceResult, cached: SourceTrackProbe?, onProbe: @escaping (SourceTrackProbe) -> Void,
         backdropURL: String?, preferences: ManualTrackPreferences, overrides: Binding<ManualTrackOverrides>,
         onPlay: @escaping (ManualTrackPick?) -> Void) {
        _model = StateObject(wrappedValue: SourceTracksModel(result: result, cached: cached, onProbe: onProbe))
        self.backdropURL = backdropURL
        self.preferences = preferences
        defaults = nil
        _overrides = overrides
        self.onPlay = onPlay
    }

    /// The prequeued stream's tracks (details › Audio & Subtitles), with what Play would pick
    /// checked rather than the client's defaults.
    init(releaseName: String, tracks: SourceTrackProbe, defaults: TrackDefaults, backdropURL: String?,
         preferences: ManualTrackPreferences, overrides: Binding<ManualTrackOverrides>,
         onPlay: @escaping (ManualTrackPick?) -> Void) {
        _model = StateObject(wrappedValue: SourceTracksModel(releaseName: releaseName, tracks: tracks))
        self.backdropURL = backdropURL
        self.preferences = preferences
        self.defaults = defaults
        _overrides = overrides
        self.onPlay = onPlay
    }

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Focus?

    enum Focus: Hashable {
        case play, retry, audio(Int), subtitle(Int)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio & Subtitles").font(.title2.weight(.semibold))
                Text(model.releaseName).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            content
        }
        .frame(maxWidth: 1500, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background { SourcePickerBackdrop(url: backdropURL) }
        .onExitCommand { dismiss() }
        .onAppear { model.start() }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            actions(retry: false)
            HStack(spacing: 24) {
                ProgressView()
                Text("Loading tracks…").foregroundStyle(.secondary)
            }
        case let .failed(message):
            actions(retry: true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load tracks").font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                Text("Play starts this source with your usual tracks.").font(.callout).foregroundStyle(.secondary)
            }
        case let .loaded(probe):
            actions(retry: false)
            lists(probe)
        }
    }

    private func actions(retry: Bool) -> some View {
        HStack(spacing: 30) {
            Button {
                dismiss()
                onPlay(pick)
            } label: {
                Label("Play", systemImage: "play.fill").padding(.horizontal, 20)
            }
            .focused($focus, equals: .play)
            if retry {
                Button { model.start() } label: {
                    Label("Retry", systemImage: "arrow.clockwise").padding(.horizontal, 20)
                }
                .focused($focus, equals: .retry)
            }
        }
        .focusSection()
        .defaultFocus($focus, .play)
    }

    /// The picks to play with: nil when nothing was changed or there are no lists (the
    /// player then uses the server's selection, as for a plain Select).
    private var pick: ManualTrackPick? {
        guard let probe = model.probe, !overrides.isEmpty else { return nil }
        return ManualTrackPick(overrides: overrides, audio: probe.audio, subtitles: probe.subtitles)
    }

    // MARK: Lists

    private func lists(_ probe: SourceTrackProbe) -> some View {
        let audio = ManualTrackSelection.filterAllowed(probe.audio, language: \.language,
                                                        allowed: preferences.allowedLanguages)
        let subtitles = ManualTrackSelection.filterAllowed(probe.subtitles, language: \.language,
                                                            allowed: preferences.allowedLanguages)
        let defaultAudio = defaults.map(\.audio)
            ?? ManualTrackSelection.defaultAudio(audio, preferredLanguage: preferences.audioLanguage,
                                                lossless: preferences.losslessAudio)
        let defaultSubtitle = defaults.map { (index: $0.subtitle, searchesOnline: $0.searchesOnline) }
            ?? ManualTrackSelection.defaultSubtitle(subtitles, language: preferences.subtitleLanguage,
                                                    mode: preferences.subtitleMode)
        let selectedAudio = overrides.audioTrack ?? defaultAudio
        let selectedSubtitle: Int? = overrides.subtitleTrack.map { $0 == ManualTrackOverrides.off ? nil : $0 }
            ?? defaultSubtitle.index
        return HStack(alignment: .top, spacing: 60) {
            column(String(localized: "Audio"), count: audio.count) {
                if audio.isEmpty {
                    Text("No audio tracks listed").foregroundStyle(.secondary)
                }
                ForEach(audio) { track in
                    row(title: TrackLabels.language(track.language), detail: TrackLabels.audioDetail(track),
                        selected: track.index == selectedAudio) {
                        overrides.audioTrack = track.index
                        log("audio", track.index)
                    }
                    .focused($focus, equals: .audio(track.index))
                }
            }
            column(String(localized: "Subtitles"), count: subtitles.count) {
                row(title: String(localized: "Off"), detail: nil, selected: selectedSubtitle == nil) {
                    overrides.subtitleTrack = ManualTrackOverrides.off
                    log("subtitle", ManualTrackOverrides.off)
                }
                .focused($focus, equals: .subtitle(ManualTrackOverrides.off))
                ForEach(subtitles) { track in
                    row(title: TrackLabels.language(track.language), detail: TrackLabels.subtitleDetail(track),
                        selected: track.index == selectedSubtitle) {
                        overrides.subtitleTrack = track.index
                        log("subtitle", track.index)
                    }
                    .focused($focus, equals: .subtitle(track.index))
                }
                if defaultSubtitle.searchesOnline, overrides.subtitleTrack == nil {
                    Label("No \(TrackLabels.language(preferences.subtitleLanguage)) subtitles here: the player searches online",
                          systemImage: "magnifyingglass")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 32)
                }
            }
        }
        .onAppear {
            Self.logDefaults(probe: probe, audio: defaultAudio, subtitle: defaultSubtitle.index, preferences: preferences)
        }
    }

    private func column<Content: View>(_ title: String, count: Int,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(title) (\(count))").font(.headline).foregroundStyle(.secondary).padding(.leading, 32)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) { content() }
                    .padding(.vertical, 12)
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .focusSection()
    }

    private func row(title: String, detail: String?, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.callout).lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).opacity(0.7).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.callout.weight(.semibold)) }
            }
        }
        .buttonStyle(SourceRowStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func log(_ kind: String, _ index: Int) {
        SourceTracksModel.log.notice("pick \(kind) stream \(index) for \"\(model.releaseName)\"")
    }

    private static func logDefaults(probe: SourceTrackProbe, audio: Int?, subtitle: Int?,
                                    preferences: ManualTrackPreferences) {
        SourceTracksModel.log.notice("defaults: audio \(audio ?? -1) (\(preferences.audioLanguage)), subtitle \(subtitle ?? -1) "
            + "(\(preferences.subtitleMode) \(preferences.subtitleLanguage)); listed \(probe.audio.count) audio, "
            + "\(probe.subtitles.count) subtitles, allowed \(preferences.allowedLanguages)")
    }
}

/// The source picker's opaque, dimmed backdrop, so the details page doesn't bleed through.
struct SourcePickerBackdrop: View {
    let url: String?

    var body: some View {
        ZStack {
            Color.black
            AsyncImage(url: Artwork.url(url, size: "w780")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color.clear }
            .blur(radius: 60)
            .overlay(Color.black.opacity(0.72))
        }
        .ignoresSafeArea()
    }
}
