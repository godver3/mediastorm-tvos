import AetherEngine
import Foundation

/// Online subtitles for one movie or episode, as the Expo player finds them
/// (`performAutoSubtitleSearch`, its manual search, and the translated-subtitle refresh).
///
/// The automatic run fires once per playback when the profile wants subtitles in a language no
/// embedded track has. In order: translate an embedded English track to that language (the
/// server translates incrementally, so the result is re-read while it grows), else search the
/// online providers and download the best match, else fall back to embedded English. A manual
/// pick from the search page replaces whatever the run found. The result is one "Online" track
/// whose cues the player's overlay draws; a newer run or pick, or closing the player, cancels
/// an older one. Every step logs as `[auto-sub]` with the Expo app's event names.
@MainActor
final class OnlineSubtitles {
    /// Subtitle-menu id of the online track (embedded ids are container stream indices, ≥ 0).
    static let trackID = -2

    struct Track {
        /// The language searched for or translated to, as asked.
        let language: String
        /// "Online: French".
        let title: String
        /// "OpenSubtitles · SDH", "Translated from English".
        let detail: String
        var cues: [SubtitleCue]
    }

    let query: APIClient.SubtitleQuery
    // Internal for `+Translation`.
    let streamPath: String
    let api = APIClient.shared
    private let log = AppLog(category: "player")

    /// Set here and by `+Translation`'s refresh.
    var track: Track?
    /// nil until `/api/settings` has answered.
    private(set) var settings: APIClient.SubtitleServerSettings?

    /// A new online track is ready (select it), or `isNew` false: the translation grew.
    var onTrack: ((Track, _ isNew: Bool) -> Void)?
    /// Fallback: show this embedded track (English) instead.
    var onSelectEmbedded: ((Int) -> Void)?
    /// A short status line; nil `hideAfter` keeps it up until the next one.
    var onStatus: ((String, _ hideAfter: TimeInterval?) -> Void)?
    var onSettings: (() -> Void)?

    // Internal for `+Translation`.
    var runTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    var runCounter = 0
    private var autoTriggered = false

    init(query: APIClient.SubtitleQuery, streamPath: String) {
        self.query = query
        self.streamPath = streamPath
    }

    /// Reads the server's provider and translation switches (for the menu's Search Online…).
    func loadSettings() async -> APIClient.SubtitleServerSettings {
        if let settings { return settings }
        let loaded = await api.subtitleServerSettings() ?? APIClient.SubtitleServerSettings()
        settings = loaded
        onSettings?()
        return loaded
    }

    /// Search Online… is worth offering: a provider is set up, or the server hasn't said yet.
    var searchAvailable: Bool { settings?.providerConfigured ?? true }

    func cancel() {
        runCounter += 1
        runTask?.cancel()
        refreshTask?.cancel()
        runTask = nil
        refreshTask = nil
    }

    // MARK: Automatic run

    /// Starts the automatic run once per playback when the profile's subtitle mode is `on`, a
    /// language is set and no embedded track (other than a forced one) is in it. While it runs
    /// the server's fallback pick, if any, stays on screen.
    func autoSearchIfNeeded(preferences: TrackPreferences, embedded: [TrackInfo], position: Double) {
        guard !autoTriggered else { return }
        let mode = preferences.subtitleMode ?? "nil"
        guard mode == "on" else { return flow("trigger_skip_mode_off", "mode=\(mode)") }
        guard let language = preferences.subtitleLanguage else { return flow("trigger_skip_no_language") }
        let container = Self.containerTracks(embedded)
        if container.contains(where: { TrackPreferences.sameLanguage($0.language, language) && !$0.isForced }) {
            return flow("trigger_skip_embedded_match", "language=\(language)")
        }
        autoTriggered = true
        cancel()
        let run = runCounter
        runTask = Task { [weak self] in
            guard let self else { return }
            var settings = await loadSettings()
            // Settings › Playback › Subtitle Translation can turn the server's switch off here.
            settings.translationEnabled = TrackSettingsStore.shared.translationEnabled(server: settings.translationEnabled)
            guard isCurrent(run) else { return }
            let translationEligible = settings.translationEnabled && !Self.isEnglish(language)
            guard settings.providerConfigured || translationEligible else {
                return flow("trigger_skip_missing_credentials", "language=\(language)")
            }
            flow("trigger_fire", "language=\(language) mode=\(mode) tracks=\(container.count)")
            await performAuto(language: language, container: container, position: position,
                              settings: settings, run: run)
        }
    }

    private func performAuto(language: String, container: [TrackInfo], position: Double,
                             settings: APIClient.SubtitleServerSettings, run: Int) async {
        flow("start", "language=\(language) provider=\(settings.providerConfigured) translate=\(settings.translationEnabled)")
        status(String(localized: "Searching for subtitles…"))

        // 1. Translate an embedded English track.
        if !Self.isEnglish(language), settings.translationEnabled {
            let english = Self.englishTrack(in: container, textOnly: true)
            flow("english_track_resolution", "stream=\(english.map { String($0.id) } ?? "none")")
            if let english, await translateTrack(english, container: container, from: "en", to: language,
                                                 position: position, run: run, manual: false) {
                return
            }
            guard isCurrent(run) else { return }
        }

        // 2. Online providers.
        guard settings.providerConfigured else {
            flow("search_skip_missing_credentials", "language=\(language)")
            return status(String(localized: "No subtitle provider configured"), hideAfter: 3)
        }
        let results: [SubtitleSearchResult]
        do {
            results = try await api.searchSubtitles(query, language: Self.searchCode(language))
        } catch {
            guard isCurrent(run) else { return }
            flow("search_error", error.localizedDescription)
            if fallBackToEnglish(container, language: language, event: "error_fallback_to_english_embedded") { return }
            flow("failed", "language=\(language)")
            return status(String(localized: "Subtitle search failed"), hideAfter: 3)
        }
        guard isCurrent(run) else { return }
        flow("search_results", "language=\(language) count=\(results.count)")
        guard let best = OnlineSubtitleMatching.selectBest(results, releaseName: query.releaseName,
                                                           season: query.season, episode: query.episode) else {
            if fallBackToEnglish(container, language: language, event: "fallback_to_english_embedded") { return }
            flow("no_results", "language=\(language)")
            return status(String(localized: "No subtitles found"), hideAfter: 3)
        }

        // 3. Download the best match; it must have cues.
        status(String(localized: "Downloading subtitles…"))
        flow("selected_online_match", "release=\(best.release) id=\(best.id) provider=\(best.provider)")
        let body = await waitForCues(phase: "external-download", attempts: 8, delay: .milliseconds(200)) { [api, query] in
            try await api.downloadSubtitle(best, query: query, language: Self.searchCode(language))
        }
        guard isCurrent(run) else { return }
        guard let body else {
            flow("external_no_cues")
            return status(String(localized: "No usable subtitles found"), hideAfter: 3)
        }
        deliver(Track(language: language, title: Self.title(language), detail: Self.detail(best), cues: WebVTT.cues(body)))
        flow("external_ready", "cues=\(track?.cues.count ?? 0)")
        status(String(localized: "Subtitles ready"), hideAfter: 2)
    }

    private func fallBackToEnglish(_ container: [TrackInfo], language: String, event: String) -> Bool {
        guard !Self.isEnglish(language), let english = Self.englishTrack(in: container, textOnly: false) else { return false }
        flow(event, "stream=\(english.id)")
        onSelectEmbedded?(english.id)
        status(String(localized: "Using English subtitles"), hideAfter: 2)
        return true
    }

    // MARK: Manual search

    func search(language: String) async throws -> [SubtitleSearchResult] {
        try await api.searchSubtitles(query, language: language)
    }

    /// A pick from the search page: downloaded and made the online track, replacing (and
    /// cancelling) anything the automatic run was doing.
    func use(_ result: SubtitleSearchResult, language: String) {
        cancel()
        let run = runCounter
        flow("manual_pick", "release=\(result.release) id=\(result.id) provider=\(result.provider) language=\(language)")
        status(String(localized: "Downloading subtitles…"))
        runTask = Task { [weak self, api, query] in
            do {
                let body = try await api.downloadSubtitle(result, query: query, language: language)
                guard let self, isCurrent(run) else { return }
                let cues = WebVTT.cues(body)
                guard !cues.isEmpty else {
                    flow("manual_no_cues")
                    return status(String(localized: "No usable subtitles found"), hideAfter: 3)
                }
                deliver(Track(language: language, title: Self.title(language), detail: Self.detail(result), cues: cues))
                flow("manual_ready", "cues=\(cues.count)")
                status(String(localized: "Subtitles ready"), hideAfter: 2)
            } catch {
                guard let self, isCurrent(run) else { return }
                flow("manual_download_failed", error.localizedDescription)
                status(String(localized: "Couldn't download subtitles"), hideAfter: 3)
            }
        }
    }

    // MARK: Helpers

    func deliver(_ new: Track) {
        refreshTask?.cancel()
        track = new
        onTrack?(new, true)
    }

    func isCurrent(_ run: Int) -> Bool { !Task.isCancelled && run == runCounter }

    func status(_ text: String, hideAfter: TimeInterval? = nil) {
        onStatus?(text, hideAfter)
    }

    func flow(_ event: String, _ details: String = "") {
        log.notice("[auto-sub] run=\(runCounter) event=\(event)\(details.isEmpty ? "" : " \(details)")")
    }

    /// Re-reads `fetch` until it has `minCues` cues or `minBytes` bytes (and at least one cue),
    /// as the Expo player's `waitForVttCues`. A failed request ends the wait; when the attempts
    /// run out, the fullest body with any cue is accepted. nil: no cues.
    func waitForCues(phase: String, attempts: Int, delay: Duration, minCues: Int = 1, minBytes: Int = .max,
                             fetch: @escaping () async throws -> String) async -> String? {
        var fullest: (body: String, cues: Int)?
        for attempt in 1...attempts {
            let body: String
            do {
                body = try await fetch()
            } catch {
                flow("probe_fetch_error", "phase=\(phase) attempt=\(attempt) error=\(error.localizedDescription)")
                return nil
            }
            guard !Task.isCancelled else { return nil }
            let cues = WebVTT.cueCount(body)
            flow("probe_attempt", "phase=\(phase) attempt=\(attempt)/\(attempts) cues=\(cues) bytes=\(body.utf8.count)")
            if cues > 0, cues > (fullest?.cues ?? 0) { fullest = (body, cues) }
            if cues > 0, cues >= minCues || body.utf8.count >= minBytes {
                flow("probe_ready", "phase=\(phase) attempt=\(attempt) cues=\(cues)")
                return body
            }
            if attempt < attempts { try? await Task.sleep(for: delay) }
        }
        flow("probe_exhausted", "phase=\(phase) maxCues=\(fullest?.cues ?? 0)")
        return fullest?.body
    }

    /// The source's own subtitle streams, in container order.
    static func containerTracks(_ tracks: [TrackInfo]) -> [TrackInfo] {
        tracks.filter { !$0.isExternal && !TrackPreferences.isClosedCaption($0.codec) }.sorted { $0.id < $1.id }
    }

    /// An English, non-forced track (one without SDH first); `textOnly` for extraction.
    static func englishTrack(in container: [TrackInfo], textOnly: Bool) -> TrackInfo? {
        let english = container.filter {
            TrackPreferences.sameLanguage($0.language, "en") && !$0.isForced && (!textOnly || isTextCodec($0.codec))
        }
        return english.first { !$0.isHearingImpaired } ?? english.first
    }

    nonisolated static func isTextCodec(_ codec: String) -> Bool {
        ["subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text"].contains(codec.lowercased())
    }

    static func isEnglish(_ language: String) -> Bool {
        language.lowercased() == "english" || TrackPreferences.sameLanguage(language, "en")
    }

    /// Two-letter code where there is one (the providers take both; legacy `fre` / `ger` they don't).
    static func searchCode(_ language: String) -> String {
        TrackPreferences.normalize(language)
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: searchCode(code)) ?? code
    }

    static func title(_ language: String) -> String {
        String(localized: "Online: \(languageName(language))")
    }

    static func detail(_ result: SubtitleSearchResult) -> String {
        var parts = [providerName(result.provider)]
        if result.hearingImpaired { parts.append("SDH") }
        return parts.joined(separator: " · ")
    }

    static func providerName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "opensubtitles", "opensubtitlescom": "OpenSubtitles"
        case "subdl": "SubDL"
        case "subsource": "SubSource"
        case "": String(localized: "Online")
        default: provider.prefix(1).uppercased() + provider.dropFirst()
        }
    }
}
