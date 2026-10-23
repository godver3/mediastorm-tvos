import AetherEngine
import Foundation

/// Translated subtitles: an embedded text track extracted to WebVTT on the server
/// (`/api/video/subtitles/start`) and translated by `/api/subtitles/translate`, which works
/// incrementally, so the result is re-read while it grows. The automatic run translates
/// embedded English; the Subtitles menu's Translate… (the Expo player's `handleTranslateTrack`)
/// translates any text track to a language the viewer picks.
extension OnlineSubtitles {
    /// Translate… is worth offering: the server's `enableTranslatedSubs` is on (or unknown).
    /// The device's Subtitle Translation setting governs only the automatic run.
    var translateAvailable: Bool { settings?.translationEnabled ?? true }

    /// Tracks Translate… can start from: the source's own subtitle streams, minus bitmap ones.
    static func translatableTracks(_ tracks: [TrackInfo]) -> [TrackInfo] {
        containerTracks(tracks).filter { !isBitmapCodec($0.codec) }
    }

    static func isBitmapCodec(_ codec: String) -> Bool {
        let c = codec.lowercased()
        return ["pgs", "hdmv", "dvd", "dvb_sub", "dvbsub", "vobsub", "xsub"].contains(where: c.contains)
    }

    /// A Translate… pick: `source` into `target`, replacing (and cancelling) whatever the
    /// automatic run or an earlier pick was doing.
    func translate(_ source: TrackInfo, container: [TrackInfo], to target: String, position: Double) {
        cancel()
        let run = runCounter
        let from = Self.sourceLanguage(of: source)
        flow("manual_translate", "stream=\(source.id) from=\(from) to=\(target)")
        status(String(localized: "Translating subtitles…"))
        runTask = Task { [weak self] in
            guard let self else { return }
            let shown = await translateTrack(source, container: container, from: from, to: target,
                                             position: position, run: run, manual: true)
            guard !shown, isCurrent(run) else { return }
            status(String(localized: "Couldn't translate subtitles"), hideAfter: 3)
        }
    }

    /// Extracts `source` and translates it, waiting until a few cues are done (or at least one
    /// when the wait runs out). True once the translation is the online track.
    func translateTrack(_ source: TrackInfo, container: [TrackInfo], from sourceLanguage: String, to language: String,
                        position: Double, run: Int, manual: Bool) async -> Bool {
        let tag = manual ? "translate_source" : "english_source"
        if !manual { status(String(localized: "Translating embedded English subtitles…")) }
        // The server numbers the source's subtitle streams in order (the closed captions the
        // engine lists are not streams).
        guard let relative = container.firstIndex(where: { $0.id == source.id }) else { return false }
        let sourcePath: String
        do {
            if !manual { status(String(localized: "Extracting & translating subtitles…")) }
            let started = try await api.startSubtitleExtract(path: streamPath, subtitleTrack: relative,
                                                             startOffset: position > 0 ? position : nil)
            sourcePath = started.subtitleUrl
            flow("\(tag)_extracted", "track=\(relative) stream=\(source.id) url=\(sourcePath)")
        } catch {
            flow("\(tag)_extract_failed", "track=\(relative) error=\(error.localizedDescription)")
            if !manual { flow("english_source_missing", "language=\(language)") }
            return false
        }
        guard isCurrent(run) else { return false }
        flow("translation_streaming", "from=\(sourceLanguage) to=\(language) source=\(sourcePath)")
        status(String(localized: "Translating subtitles…"))
        let body = await waitForCues(phase: manual ? "manual-translation" : "translation", attempts: 30,
                                     delay: .seconds(2), minCues: 4, minBytes: 1200) { [api] in
            try await api.translateSubtitles(sourcePath: sourcePath, from: sourceLanguage, to: language)
        }
        guard isCurrent(run) else { return false }
        guard let body else {
            flow("translation_no_cues")
            return false
        }
        let title = manual ? String(localized: "Translated: \(Self.languageName(language))") : Self.title(language)
        let detail = manual ? String(localized: "From \(Self.languageName(sourceLanguage))")
            : String(localized: "Translated from English")
        deliver(Track(language: language, title: title, detail: detail, cues: WebVTT.cues(body)))
        flow("translation_ready", "cues=\(track?.cues.count ?? 0)")
        status(String(localized: "Translated subtitles ready"), hideAfter: 2)
        refreshTranslation(sourcePath: sourcePath, from: sourceLanguage, to: language, body: body, run: run)
        return true
    }

    /// The translation keeps growing as the extraction and the server's per-request budget
    /// allow: re-read it every 10 s (after 10 s) and show more cues as they land, until six
    /// reads in a row bring nothing new.
    private func refreshTranslation(sourcePath: String, from sourceLanguage: String, to language: String,
                                    body: String, run: Int) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self, api] in
            var lastCount = WebVTT.cueCount(body)
            var lastLength = body.utf8.count
            var unchanged = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                guard let text = try? await api.translateSubtitles(sourcePath: sourcePath, from: sourceLanguage,
                                                                   to: language) else { continue }
                guard let self, isCurrent(run) else { return }
                let count = WebVTT.cueCount(text)
                let length = text.utf8.count
                if count > lastCount || length - lastLength > 50 {
                    flow("translation_refresh", "cues \(lastCount)->\(count) bytes \(lastLength)->\(length)")
                    unchanged = 0
                    lastCount = count
                    lastLength = length
                    guard var current = track else { return }
                    current.cues = WebVTT.cues(text)
                    track = current
                    onTrack?(current, false)
                } else {
                    unchanged += 1
                    if unchanged >= 6 { return flow("translation_stable", "cues=\(count)") }
                }
            }
        }
    }

    // MARK: Source language

    /// The track's language as a two-letter code, as the Expo player resolves it: the stream's
    /// language tag, else a language named in its title, else English.
    static func sourceLanguage(of track: TrackInfo) -> String {
        if let raw = track.language?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty, raw != "und" {
            return languageCodes[raw] ?? TrackPreferences.normalize(raw)
        }
        let words = track.name.lowercased()
            .split { $0.isWhitespace || $0 == "·" || $0 == "," }
            .map(String.init)
        if let named = words.lazy.compactMap({ languageCodes[$0] }).first(where: { $0 != "en" }) { return named }
        return words.lazy.filter { $0.count == 3 }.compactMap { languageCodes[$0] }.first ?? "en"
    }

    /// The Expo player's `langMap`: codes, English names and native names to ISO 639-1.
    private static let languageCodes: [String: String] = {
        let groups: [String: [String]] = [
            "en": ["eng", "english"], "fr": ["fre", "fra", "french", "français"],
            "de": ["ger", "deu", "german", "deutsch"], "es": ["spa", "spanish", "español"],
            "it": ["ita", "italian", "italiano"], "pt": ["por", "portuguese", "português"],
            "nl": ["dut", "nld", "dutch", "nederlands"], "pl": ["pol", "polish", "polski"],
            "ru": ["rus", "russian", "русский"], "ja": ["jpn", "japanese", "日本語"],
            "ko": ["kor", "korean"], "zh": ["chi", "zho", "chinese"], "ar": ["ara", "arabic"],
            "he": ["heb", "hebrew"], "sv": ["swe", "swedish"], "no": ["nor", "nob", "nno", "norwegian"],
            "da": ["dan", "danish"], "fi": ["fin", "finnish"], "hr": ["hrv", "croatian"],
            "sr": ["srp", "serbian"], "bs": ["bos", "bosnian"],
        ]
        var map: [String: String] = [:]
        for (code, aliases) in groups {
            map[code] = code
            for alias in aliases { map[alias] = code }
        }
        return map
    }()
}
