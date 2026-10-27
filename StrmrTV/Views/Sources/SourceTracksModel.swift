import Foundation

/// A source's track lists plus the user's picks, carried from the source picker to playback.
struct ManualTrackPick {
    let overrides: ManualTrackOverrides
    let audio: [ProbedAudioTrack]
    let subtitles: [ProbedSubtitleTrack]

    /// The server's selection for the resolved stream with the picks laid over it.
    func selection(over server: TrackSelection?) -> TrackSelection {
        ManualTrackSelection.apply(overrides, to: server, audio: audio, subtitles: subtitles)
    }

    /// The probe's lists for `ClientTrackSelector` (Settings › Playback's overrides).
    var audioStreams: [ClientTrackSelector.Stream] {
        audio.map { .init(index: $0.index, language: $0.language, title: $0.title ?? "", codec: $0.codec ?? "", forced: false) }
    }

    var subtitleStreams: [ClientTrackSelector.Stream] {
        subtitles.map {
            .init(index: $0.index, language: $0.language, title: $0.title ?? "", codec: $0.codec ?? "", forced: $0.isForced)
        }
    }
}

extension ManualTrackPreferences {
    /// The defaults a long press shows: the title's content preference, under this device's
    /// Settings › Playback overrides (which the player also puts first), over the profile's
    /// playback settings. Reads the profile's settings if they are stale.
    @MainActor
    static func current(content: ContentPreference?) async -> ManualTrackPreferences {
        let store = TrackSettingsStore.shared
        await store.loadProfileValues()
        func first(_ values: String?...) -> String {
            values.lazy.compactMap { $0 }.first { !$0.isEmpty } ?? ""
        }
        let mode = first(store.subtitleMode, content?.subtitleMode, store.server.subtitleMode)
        return ManualTrackPreferences(
            audioLanguage: first(store.audioLanguage, content?.audioLanguage, store.server.audioLanguage),
            subtitleLanguage: first(store.subtitleLanguage, content?.subtitleLanguage, store.server.subtitleLanguage),
            subtitleMode: TrackSettingsStore.normalizeMode(mode.isEmpty ? "off" : mode) ?? "off",
            allowedLanguages: store.server.allowedLanguages,
            losslessAudio: store.losslessAudio)
    }
}

/// Probes one source for its tracks on a long press in the source picker, polling while a
/// debrid probe is still running (every 2 s, as Expo does), or holds the track lists a
/// resolved prequeue already has (no probe). Logs as `[manual-tracks]`.
@MainActor
final class SourceTracksModel: ObservableObject {
    enum State {
        case loading
        case loaded(SourceTrackProbe)
        case failed(String)
    }

    static let log = AppLog(category: "manual-tracks")

    @Published private(set) var state: State = .loading
    /// The source to probe; nil when the lists came with a resolved prequeue.
    let result: SourceResult?
    /// The release name the page heads with.
    let releaseName: String
    private var task: Task<Void, Never>?
    /// Called with each finished probe, so the picker can cache it and update the row's badge.
    private let onProbe: (SourceTrackProbe) -> Void

    init(result: SourceResult, cached: SourceTrackProbe?, onProbe: @escaping (SourceTrackProbe) -> Void) {
        self.result = result
        let name = result.attributes["raw_title"] ?? result.title
        releaseName = name.components(separatedBy: "\n").first ?? result.title
        self.onProbe = onProbe
        if let cached { state = .loaded(cached) }
    }

    /// The prequeued stream's lists, as the details page's Audio & Subtitles shows them.
    init(releaseName: String, tracks: SourceTrackProbe) {
        result = nil
        self.releaseName = releaseName
        onProbe = { _ in }
        state = .loaded(tracks)
    }

    var probe: SourceTrackProbe? {
        if case let .loaded(probe) = state { return probe }
        return nil
    }

    func start() {
        guard probe == nil, let result else { return }
        task?.cancel()
        state = .loading
        task = Task { [weak self] in
            let started = Date()
            Self.log.notice("probe start: \(result.serviceType) \"\(result.title)\"")
            do {
                var probe = try await APIClient.shared.probeTracks(result)
                var polls = 0
                while probe.tracksLoading, polls < 45, !Task.isCancelled {
                    polls += 1
                    try await Task.sleep(for: .seconds(2))
                    probe = try await APIClient.shared.probeTracks(result)
                }
                guard let self, !Task.isCancelled else { return }
                let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
                Self.log.notice("probe done in \(elapsed)s: playable=\(probe.playable) audio=\(probe.audio.count) "
                    + "subtitles=\(probe.subtitles.count) polls=\(polls) error=\(probe.error ?? "-")")
                self.onProbe(probe)
                if probe.audio.isEmpty, probe.subtitles.isEmpty {
                    self.state = .failed(probe.tracksLoading
                        ? String(localized: "The server is still reading this source's tracks.")
                        : probe.error ?? String(localized: "No track information is available for this source."))
                } else {
                    self.state = .loaded(probe)
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                Self.log.error("probe failed: \(error.localizedDescription)")
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

// MARK: - Row text

enum TrackLabels {
    /// The language's name in the device language; "Unknown" for none or `und`.
    static func language(_ code: String?) -> String {
        guard let code = code?.trimmingCharacters(in: .whitespaces), !code.isEmpty, code.lowercased() != "und" else {
            return String(localized: "Unknown")
        }
        let normalized = TrackPreferences.normalize(code)
        return Locale.current.localizedString(forLanguageCode: normalized) ?? code.uppercased()
    }

    /// "E-AC-3 · Atmos · Director's Commentary".
    static func audioDetail(_ track: ProbedAudioTrack) -> String {
        var parts: [String] = []
        let codec = format(track.codec)
        if !codec.isEmpty { parts.append(codec) }
        if let profile = track.profile, !profile.isEmpty, profile.lowercased() != track.codec?.lowercased() {
            parts.append(profile)
        }
        if let title = track.title, !title.isEmpty, title != language(track.language) { parts.append(title) }
        return parts.joined(separator: " · ")
    }

    /// "Forced · SDH · PGS".
    static func subtitleDetail(_ track: ProbedSubtitleTrack) -> String {
        var parts: [String] = []
        if track.isForced { parts.append(String(localized: "Forced")) }
        let title = track.title ?? ""
        if track.isSDH, !title.localizedCaseInsensitiveContains("SDH") { parts.append("SDH") }
        if !title.isEmpty, title != language(track.language) { parts.append(title) }
        if track.isBitmap ?? false {
            parts.append(track.bitmapType ?? "PGS")
        } else {
            let codec = format(track.codec)
            if !codec.isEmpty { parts.append(codec) }
        }
        return parts.joined(separator: " · ")
    }

    static func format(_ codec: String?) -> String {
        switch (codec ?? "").lowercased() {
        case "": ""
        case "eac3": "E-AC-3"
        case "ac3": "AC-3"
        case "truehd": "TrueHD"
        case "dts": "DTS"
        case "subrip", "srt": "SRT"
        case "ass", "ssa": "ASS"
        case "webvtt": "WebVTT"
        case "mov_text": "Text"
        case "hdmv_pgs_subtitle", "pgssub": "PGS"
        case "dvd_subtitle", "dvdsub": "VobSub"
        case "dvb_subtitle", "dvbsub": "DVB"
        default: (codec ?? "").uppercased()
        }
    }
}
