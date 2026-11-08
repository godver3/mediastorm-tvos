#if os(iOS)
import SwiftUI

/// A source's (or the prequeued stream's) audio and subtitle tracks as a grouped list, the
/// phone form of the TV's `SourceTracksView`: the defaults are checked, a tap changes the pick,
/// Play starts the stream with the picks. Probing runs through the shared `SourceTracksModel`.
struct MobileTracksView: View {
    @StateObject private var model: SourceTracksModel
    /// Checked before any pick, in place of the defaults worked out from `preferences`.
    let defaults: TrackDefaults?
    let preferences: ManualTrackPreferences
    @Binding var overrides: ManualTrackOverrides
    let playLabel: String
    /// Shown as its own sheet (with Cancel), not pushed in the source picker's stack.
    let inSheet: Bool
    let onPlay: (ManualTrackPick?) -> Void

    @Environment(\.dismiss) private var dismiss

    init(model: @autoclosure @escaping () -> SourceTracksModel, defaults: TrackDefaults?,
         preferences: ManualTrackPreferences, overrides: Binding<ManualTrackOverrides>, playLabel: String,
         inSheet: Bool, onPlay: @escaping (ManualTrackPick?) -> Void) {
        _model = StateObject(wrappedValue: model())
        self.defaults = defaults
        self.preferences = preferences
        _overrides = overrides
        self.playLabel = playLabel
        self.inSheet = inSheet
        self.onPlay = onPlay
    }

    var body: some View {
        if inSheet {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        List {
            Section {
                Text(model.releaseName).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            switch model.state {
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading tracks…").foregroundStyle(.secondary)
                    }
                }
            case let .failed(message):
                Section {
                    ContentUnavailableView {
                        Label("Couldn't Load Tracks", systemImage: "waveform.slash")
                    } description: {
                        Text("\(message)\nPlay starts this source with your usual tracks.")
                    } actions: {
                        Button("Retry") { model.start() }
                    }
                }
            case let .loaded(probe):
                lists(probe)
            }
        }
        .navigationTitle("Audio & Subtitles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inSheet {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                    onPlay(pick)
                } label: {
                    Label(playLabel, systemImage: "play.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.cancel() }
    }

    private var pick: ManualTrackPick? {
        guard let probe = model.probe, !overrides.isEmpty else { return nil }
        return ManualTrackPick(overrides: overrides, audio: probe.audio, subtitles: probe.subtitles)
    }

    @ViewBuilder
    private func lists(_ probe: SourceTrackProbe) -> some View {
        let audio = ManualTrackSelection.filterAllowed(probe.audio, language: \.language,
                                                        allowed: preferences.allowedLanguages)
        let subtitles = ManualTrackSelection.filterAllowed(probe.subtitles, language: \.language,
                                                            allowed: preferences.allowedLanguages)
        let defaultAudio = defaults.map(\.audio)
            ?? ManualTrackSelection.defaultAudio(audio, preferredLanguage: preferences.audioLanguage,
                                                lossless: preferences.losslessAudio)
        let defaultSubtitle = defaults.map { (index: $0.subtitle, searchesOnline: $0.searchesOnline) }
            ?? ManualTrackSelection.defaultSubtitle(
                subtitles, language: preferences.subtitleLanguage, mode: preferences.subtitleMode,
                audioLanguage: audio.first { $0.index == defaultAudio }?.language)
        let selectedAudio = overrides.audioTrack ?? defaultAudio
        let selectedSubtitle: Int? = overrides.subtitleTrack.map { $0 == ManualTrackOverrides.off ? nil : $0 }
            ?? defaultSubtitle.index
        Section("Audio (\(audio.count))") {
            if audio.isEmpty { Text("No audio tracks listed").foregroundStyle(.secondary) }
            ForEach(audio) { track in
                row(TrackLabels.language(track.language), TrackLabels.audioDetail(track), selected: track.index == selectedAudio) {
                    overrides.audioTrack = track.index
                }
            }
        }
        Section {
            row(String(localized: "Off"), nil, selected: selectedSubtitle == nil) {
                overrides.subtitleTrack = ManualTrackOverrides.off
            }
            ForEach(subtitles) { track in
                row(TrackLabels.language(track.language), TrackLabels.subtitleDetail(track),
                    selected: track.index == selectedSubtitle) {
                    overrides.subtitleTrack = track.index
                }
            }
        } header: {
            Text("Subtitles (\(subtitles.count))")
        } footer: {
            if defaultSubtitle.searchesOnline, overrides.subtitleTrack == nil {
                Text("No \(TrackLabels.language(preferences.subtitleLanguage)) subtitles here: the player searches online.")
            }
        }
    }

    private func row(_ title: String, _ detail: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A library copies list (Versions), with Stream Instead when Play opened it.
struct MobileVersionsSheet: View {
    let heading: String
    let versions: [LibraryVersion]
    let onStream: (() -> Void)?
    let onPick: (LibraryVersion) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(versions) { version in
                        Button {
                            dismiss()
                            onPick(version)
                        } label: {
                            LibraryVersionRow(version: version)
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text(versions.count == 1 ? String(localized: "1 version in your libraries")
                                             : String(localized: "\(versions.count) versions in your libraries"))
                }
                if let onStream {
                    Section {
                        Button {
                            dismiss()
                            onStream()
                        } label: {
                            Label("Stream Instead", systemImage: "icloud.and.arrow.down")
                        }
                    }
                }
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
#endif
