import Foundation

// The Expo manual source picker's track listing (`features/details/manual-selection.tsx`:
// `findSelectedAudioTrack`, `findSelectedSubtitleTrack`, `ManualTrackOverrides`) and
// `utils/player-language-filter.ts` (`filterPlayerTracksByAllowedLanguages`), ported as pure
// functions. Keep them in step with the TypeScript.

/// An audio stream from a source probe (`/api/usenet/health` with `probeForTracks`, or
/// `/api/debrid/cached` with `verifyUncached`). `index` is the container (ffprobe) stream number.
struct ProbedAudioTrack: Decodable, Hashable, Identifiable {
    let index: Int
    let language: String?
    let codec: String?
    let profile: String?
    let title: String?
    var id: Int { index }

    init(index: Int, language: String? = nil, codec: String? = nil, profile: String? = nil, title: String? = nil) {
        self.index = index
        self.language = language
        self.codec = codec
        self.profile = profile
        self.title = title
    }
}

/// A subtitle stream from a source probe; `index` is the container stream number.
struct ProbedSubtitleTrack: Decodable, Hashable, Identifiable {
    let index: Int
    let language: String?
    let codec: String?
    let title: String?
    let forced: Bool?
    let isBitmap: Bool?
    let bitmapType: String?
    var id: Int { index }

    init(index: Int, language: String? = nil, codec: String? = nil, title: String? = nil,
         forced: Bool = false, isBitmap: Bool = false, bitmapType: String? = nil) {
        self.index = index
        self.language = language
        self.codec = codec
        self.title = title
        self.forced = forced
        self.isBitmap = isBitmap
        self.bitmapType = bitmapType
    }

    var isForced: Bool { forced ?? false }
    /// Subtitles for the deaf and hard of hearing, from the title (as Expo reads it).
    var isSDH: Bool {
        let t = (title ?? "").lowercased()
        return t.contains("sdh") || t.contains("deaf") || t.contains("hard of hearing")
    }
}

/// The user's picks for one result (Expo `ManualTrackOverrides`): container stream indexes;
/// a subtitle of `ManualTrackOverrides.off` turns subtitles off. nil follows the default.
struct ManualTrackOverrides: Hashable {
    static let off = -1
    var audioTrack: Int?
    var subtitleTrack: Int?

    var isEmpty: Bool { audioTrack == nil && subtitleTrack == nil }
}

/// The preferences the defaults are picked from: the title's content preference over the
/// profile's (and this device's) playback settings, as Expo layers them.
struct ManualTrackPreferences: Hashable {
    var audioLanguage = ""
    var subtitleLanguage = ""
    /// `off`, `forced-only` or `on`.
    var subtitleMode = "off"
    var allowedLanguages: [String] = []
    /// Settings › Playback › Audio Format is Lossless.
    var losslessAudio = false
}

enum ManualTrackSelection {
    // MARK: Defaults (Expo `findSelectedAudioTrack` / `findSelectedSubtitleTrack`)

    static let compatibleAudioCodecs: Set<String> = ["aac", "ac3", "eac3", "mp3"]
    static let trueHDCodecs: Set<String> = ["truehd", "mlp"]

    static func isCommentary(_ title: String?) -> Bool { ClientTrackSelector.isCommentary(title ?? "") }

    /// Expo's loose match: exact, or either string containing the other, on language or title.
    /// A regional preference (`fr-CA`) matches its language; `defaultAudio` prefers the dub.
    static func matchesLanguage(_ language: String?, _ title: String?, _ preference: String) -> Bool {
        guard !preference.isEmpty else { return false }
        if RegionalAudio.variant(preference) != nil {
            return ClientTrackSelector.matches(language ?? "", title ?? "", preference)
        }
        let lang = (language ?? "").lowercased()
        let t = (title ?? "").lowercased()
        let pref = preference.lowercased()
        if lang == pref || t == pref { return true }
        if !lang.isEmpty, lang.contains(pref) || pref.contains(lang) { return true }
        if !t.isEmpty, t.contains(pref) || pref.contains(t) { return true }
        return false
    }

    /// First compatible codec without commentary, then anything but TrueHD without commentary,
    /// then the first track.
    static func firstCompatibleAudio(_ tracks: [ProbedAudioTrack]) -> Int? {
        let codec = { (t: ProbedAudioTrack) in (t.codec ?? "").lowercased() }
        if let t = tracks.first(where: { compatibleAudioCodecs.contains(codec($0)) && !isCommentary($0.title) }) {
            return t.index
        }
        if let t = tracks.first(where: { !trueHDCodecs.contains(codec($0)) && !isCommentary($0.title) }) {
            return t.index
        }
        return tracks.first?.index
    }

    /// The audio track preselected for `tracks` (container index), nil with no tracks.
    /// `lossless` puts TrueHD, then DTS / FLAC / PCM, first, as the player's pick does.
    static func defaultAudio(_ tracks: [ProbedAudioTrack], preferredLanguage: String, lossless: Bool = false) -> Int? {
        guard !tracks.isEmpty else { return nil }
        let pref = preferredLanguage.lowercased()
        guard !pref.isEmpty else { return firstCompatibleAudio(tracks) }
        let codec = { (t: ProbedAudioTrack) in (t.codec ?? "").lowercased() }
        let losslessClasses: [(ProbedAudioTrack) -> Bool] = [
            { trueHDCodecs.contains(codec($0)) },
            { ClientTrackSelector.isLossless(codec($0)) },
        ]
        let classes: [(ProbedAudioTrack) -> Bool] = (lossless ? losslessClasses : []) + [
            { compatibleAudioCodecs.contains(codec($0)) },
            { !trueHDCodecs.contains(codec($0)) },
            { _ in true },
        ]
        if let variant = RegionalAudio.variant(pref) {
            for codecClass in classes {
                if let hit = tracks.first(where: {
                    matchesLanguage($0.language, $0.title, pref) && codecClass($0) && !isCommentary($0.title)
                        && RegionalAudio.matches(variant, language: $0.language, title: $0.title)
                }) {
                    return hit.index
                }
            }
        }
        for allowCommentary in [false, true] {
            for codecClass in classes {
                if let hit = tracks.first(where: {
                    matchesLanguage($0.language, $0.title, pref) && codecClass($0)
                        && (allowCommentary || !isCommentary($0.title))
                }) {
                    return hit.index
                }
            }
        }
        return firstCompatibleAudio(tracks)
    }

    /// The subtitle preselected (container index; nil = off) and whether the player would
    /// search online for one instead.
    static func defaultSubtitle(_ tracks: [ProbedSubtitleTrack], language: String,
                                mode: String) -> (index: Int?, searchesOnline: Bool) {
        let lang = language.lowercased()
        if mode == "off" { return (nil, false) }
        guard !tracks.isEmpty else { return (nil, mode == "on" && !lang.isEmpty) }
        guard !lang.isEmpty else { return (nil, false) }
        let matching = { (t: ProbedSubtitleTrack) in matchesLanguage(t.language, t.title, lang) }
        if mode == "forced-only" {
            return (tracks.first { $0.isForced && matching($0) }?.index, false)
        }
        // "on": SDH, then regular, then forced.
        if let t = tracks.first(where: { !$0.isForced && $0.isSDH && matching($0) }) { return (t.index, false) }
        if let t = tracks.first(where: { !$0.isForced && !$0.isSDH && matching($0) }) { return (t.index, false) }
        if let t = tracks.first(where: { $0.isForced && matching($0) }) { return (t.index, false) }
        return (nil, true)
    }

    // MARK: Allowed languages (`player-language-filter.ts`)

    private static let languageAliases: [String: String] = {
        let options: [(String, String, String)] = [
            ("en", "eng", "english"), ("fr", "fra", "french"), ("es", "spa", "spanish"), ("de", "deu", "german"),
            ("it", "ita", "italian"), ("pt", "por", "portuguese"), ("nl", "nld", "dutch"), ("pl", "pol", "polish"),
            ("ru", "rus", "russian"), ("ja", "jpn", "japanese"), ("ko", "kor", "korean"), ("zh", "zho", "chinese"),
            ("ar", "ara", "arabic"), ("he", "heb", "hebrew"), ("sv", "swe", "swedish"), ("no", "nor", "norwegian"),
            ("da", "dan", "danish"), ("fi", "fin", "finnish"), ("hr", "hrv", "croatian"), ("sr", "srp", "serbian"),
            ("bs", "bos", "bosnian"),
        ]
        var map: [String: String] = ["fre": "fra", "ger": "deu", "dut": "nld", "chi": "zho"]
        for (code, setting, name) in options {
            map[code] = setting
            map[setting] = setting
            map[name] = setting
        }
        return map
    }()

    static func canonicalLanguage(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespaces).lowercased(), !normalized.isEmpty else {
            return nil
        }
        if let exact = languageAliases[normalized] { return exact }
        let primary = normalized.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? normalized
        if let match = languageAliases[primary] { return match }
        for token in normalized.split(whereSeparator: { !("a"..."z").contains($0) }) {
            if let match = languageAliases[String(token)] { return match }
        }
        return normalized.count == 3 ? normalized : nil
    }

    static func isAllowed(_ language: String?, allowed: [String], allowUnknown: Bool = false) -> Bool {
        guard !allowed.isEmpty else { return true }
        guard let canonical = canonicalLanguage(language) else { return allowUnknown }
        return Set(allowed.compactMap(canonicalLanguage)).contains(canonical)
    }

    /// The tracks in the profile's allowed languages (unknown languages kept); every track when
    /// none is allowed or nothing would be left.
    static func filterAllowed<T>(_ tracks: [T], language: (T) -> String?, allowed: [String]) -> [T] {
        guard !allowed.isEmpty, tracks.contains(where: { isAllowed(language($0), allowed: allowed) }) else {
            return tracks
        }
        return tracks.filter { isAllowed(language($0), allowed: allowed, allowUnknown: true) }
    }

    // MARK: Into the player

    /// The server's selection with the user's picks laid over it, for `TrackPreferences`.
    /// `streamIndex` is the probe's container index; `typeIndex` and the language rank come
    /// from the full probe lists, the player's fallback when the stream numbers differ.
    static func apply(_ overrides: ManualTrackOverrides, to server: TrackSelection?,
                      audio: [ProbedAudioTrack], subtitles: [ProbedSubtitleTrack]) -> TrackSelection {
        var audioPick = server?.audio
        if let index = overrides.audioTrack, let track = audio.first(where: { $0.index == index }) {
            audioPick = describe(index: index, language: track.language, codec: track.codec, title: track.title,
                                 forced: nil, bitmap: nil, in: audio.map { ($0.index, $0.language) })
        }
        var subtitlePick = server?.subtitle
        var textPick = server?.textSubtitle
        var mode = server?.subtitleMode
        var subtitleLanguage = server?.subtitleLanguage
        if let index = overrides.subtitleTrack {
            if index == ManualTrackOverrides.off {
                subtitlePick = nil
                textPick = nil
                mode = "off"
            } else if let track = subtitles.first(where: { $0.index == index }) {
                subtitlePick = describe(index: index, language: track.language, codec: track.codec,
                                        title: track.title, forced: track.forced, bitmap: track.isBitmap,
                                        in: subtitles.map { ($0.index, $0.language) })
                textPick = (track.isBitmap ?? false) ? nil : subtitlePick
                if mode == nil || mode == "off" { mode = track.isForced ? "forced-only" : "on" }
                if let language = track.language, !language.isEmpty { subtitleLanguage = language }
            }
        }
        return TrackSelection(audio: audioPick, subtitle: subtitlePick, textSubtitle: textPick,
                              audioLanguage: server?.audioLanguage, subtitleLanguage: subtitleLanguage,
                              subtitleMode: mode)
    }

    private static func describe(index: Int, language: String?, codec: String?, title: String?, forced: Bool?,
                                 bitmap: Bool?, in list: [(index: Int, language: String?)]) -> SelectedTrack {
        let typeIndex = list.firstIndex { $0.index == index } ?? 0
        let same = list.filter { TrackPreferences.sameLanguage($0.language, language) }
        let rank = same.firstIndex { $0.index == index } ?? 0
        let lang = (language?.isEmpty ?? true) ? nil : language
        return SelectedTrack(streamIndex: index, typeIndex: typeIndex, language: lang, languageCode: lang,
                             languageIndex: rank, languageCount: same.count, codec: codec, title: title,
                             forced: forced, bitmap: bitmap)
    }
}
