import AetherEngine
import Foundation

/// The profile's audio / subtitle choice for one stream, as resolved by the backend
/// (prequeue status or `/playback/resolve`) from the user's language settings and
/// per-title preferences.
struct TrackPreferences {
    /// Container stream index of the preferred audio track: the engine's load-time pick
    /// (ffprobe and AetherEngine both number streams the libav way).
    let audioStreamIndex: Int?
    /// The server's explicit audio choice, re-checked against the engine's track list.
    let audio: SelectedTrack?
    /// The subtitle to preselect. nil = subtitles off (or nothing embedded matched).
    let subtitle: SelectedTrack?
    private let subtitleModeOff: Bool
    /// The profile's subtitle language (ISO 639-2) and canonical mode (`off`, `forced-only`,
    /// `on`) the pick was made from; nil from legacy servers. Online subtitles key off these.
    let subtitleLanguage: String?
    let subtitleMode: String?
    /// Legacy servers: language of the preferred subtitle and its rank among same-language tracks.
    private let legacySubtitle: (language: String?, sameLanguageRank: Int)?
    /// Picked on this device from Settings › Playback's overrides (`ClientTrackSelector`), or
    /// by hand in the source list; either way the device overrides are not applied again.
    var isClientPick = false
    /// The subtitle (or Off) was picked by hand in the source list: no automatic online search.
    var subtitlePickedByHand = false
    /// A library file: no server pick, so the player chooses from the file's own streams on this
    /// device (`devicePick`) once the engine has read them.
    var pickOnDevice = false
    /// The server's selection this was made from (nil from legacy servers).
    let selection: TrackSelection?

    /// No backend preference: the engine falls back to the device language for audio and
    /// leaves subtitles off.
    static let none = TrackPreferences(selection: nil)

    /// A library file's starting point: picked on the device after the engine loads.
    static var library: TrackPreferences {
        var tracks = TrackPreferences(selection: nil)
        tracks.pickOnDevice = true
        return tracks
    }

    init(selection: TrackSelection?) {
        self.selection = selection
        audio = selection?.audio
        audioStreamIndex = audio?.streamIndex
        // The server's own pick, bitmap or not: `SubtitleOverlayView` draws text and bitmap
        // (PGS / DVB / DVD) cues alike.
        subtitleModeOff = selection?.subtitleMode == "off"
        subtitle = subtitleModeOff ? nil : selection?.subtitle
        subtitleLanguage = selection?.subtitleLanguage.flatMap { $0.isEmpty ? nil : $0 }
        subtitleMode = selection?.subtitleMode
        legacySubtitle = nil
    }

    init(_ status: PrequeueStatus) {
        if let selection = status.trackSelection {
            self.init(selection: selection)
            return
        }
        let audio = status.selectedAudioTrack.flatMap { $0 >= 0 ? $0 : nil }
        // The legacy pick is the track's `index` (the container stream number in
        // practice); fall back to treating it as a list position.
        var legacy: (language: String?, sameLanguageRank: Int)?
        if let pick = status.selectedSubtitleTrack, pick >= 0, let tracks = status.subtitleTracks,
           let position = tracks.firstIndex(where: { $0.index == pick }) ?? (pick < tracks.count ? pick : nil) {
            let language = tracks[position].language
            legacy = (language, tracks[..<position].filter { Self.sameLanguage($0.language, language) }.count)
        }
        self.init(audioStreamIndex: audio, legacySubtitle: legacy)
    }

    private init(audioStreamIndex: Int?, legacySubtitle: (language: String?, sameLanguageRank: Int)?) {
        self.audioStreamIndex = audioStreamIndex
        audio = nil
        subtitle = nil
        subtitleModeOff = false
        selection = nil
        subtitleLanguage = nil
        subtitleMode = nil
        self.legacySubtitle = legacySubtitle
    }

    // MARK: Mapping onto AetherEngine

    /// The engine audio track (`TrackInfo.id`) for the server's pick: by `typeIndex`, else
    /// language + `languageIndex`. nil when there is no pick or nothing matches.
    func audioTrackID(in tracks: [TrackInfo]) -> Int? {
        guard let audio else { return nil }
        return Self.match(audio, in: tracks.filter { !$0.isExternal }.sorted { $0.id < $1.id })?.id
    }

    /// The server explicitly turned subtitles off for this stream (mode `off`).
    var subtitlesExplicitlyOff: Bool { subtitleModeOff }

    /// The engine subtitle track (`TrackInfo.id`, the container stream index) for the
    /// preferred subtitle, selected with `selectSubtitleTrack(index:)` on either route.
    func subtitleTrackID(in subtitleTracks: [TrackInfo]) -> Int? {
        let container = subtitleTracks.filter { !$0.isExternal && !Self.isClosedCaption($0.codec) }.sorted { $0.id < $1.id }
        if let subtitle { return Self.match(subtitle, in: container)?.id }
        guard let legacySubtitle else { return nil }
        let same = container.filter { Self.sameLanguage($0.language, legacySubtitle.language) }
        return same.isEmpty ? nil : same[min(legacySubtitle.sameLanguageRank, same.count - 1)].id
    }

    private static func match(_ pick: SelectedTrack, in tracks: [TrackInfo]) -> TrackInfo? {
        let language = pick.languageCode ?? pick.language
        if let exact = tracks.first(where: { $0.id == pick.streamIndex }),
           language == nil || sameLanguage(exact.language, language) {
            return exact
        }
        if tracks.indices.contains(pick.typeIndex) {
            let candidate = tracks[pick.typeIndex]
            if language == nil || sameLanguage(candidate.language, language) { return candidate }
        }
        let sameLanguage = tracks.filter { Self.sameLanguage($0.language, language) }
        return sameLanguage.isEmpty ? nil : sameLanguage[min(pick.languageIndex, sameLanguage.count - 1)]
    }

    /// Mirrors AetherEngine's internal closed-caption classifier.
    static func isClosedCaption(_ codec: String) -> Bool {
        ["eia_608", "eia_708", "cea708", "cea_708"].contains(codec.lowercased())
    }

    /// Fallback first-frame audio pick when the backend expresses no preference.
    static var deviceLanguages: [String] {
        Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
    }

    /// Compares ISO 639-1/639-2 (B or T) tags by normalizing both through Locale.
    static func sameLanguage(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return normalize(a) == normalize(b)
    }

    /// ISO 639-1 where one exists (`fre`, `fra` and `fr` all give `fr`), else the tag lowercased.
    static func normalize(_ tag: String) -> String {
        let lower = tag.lowercased()
        let bibliographic = ["ger": "deu", "fre": "fra", "dut": "nld", "chi": "zho", "cze": "ces", "gre": "ell", "per": "fas", "rum": "ron", "slo": "slk", "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "geo": "kat", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa", "tib": "bod", "wel": "cym"]
        let code = bibliographic[lower] ?? lower
        return Locale.Language(identifier: code).languageCode?.identifier(.alpha2) ?? code
    }
}

extension TrackPreferences {
    /// Settings › Playback's overrides applied over the server's `selection`, choosing from the
    /// source's streams as the server would; nil with every override at Default. What isn't
    /// overridden keeps the server's pick (its per-title preferences included).
    @MainActor
    static func overridden(_ selection: TrackSelection?, audio: [ClientTrackSelector.Stream],
                           subtitles: [ClientTrackSelector.Stream]) -> TrackPreferences? {
        let store = TrackSettingsStore.shared
        guard store.overridesTracks else { return nil }
        let preferences = devicePreferences(over: selection)
        let client = ClientTrackSelector.select(audio: audio, subtitles: subtitles, preferences: preferences)
        let keepAudio = store.audioLanguage == nil && !store.losslessAudio && selection != nil
        let keepSubtitle = store.subtitleMode == nil && store.subtitleLanguage == nil && selection != nil
        let merged = TrackSelection(
            // Lossless alone with no language to pick in keeps the server's track.
            audio: keepAudio ? selection?.audio : client.audio ?? (store.audioLanguage == nil ? selection?.audio : nil),
            subtitle: keepSubtitle ? selection?.subtitle : client.subtitle,
            textSubtitle: keepSubtitle ? selection?.textSubtitle : client.textSubtitle,
            audioLanguage: preferences.audioLanguage, subtitleLanguage: preferences.subtitleLanguage,
            subtitleMode: preferences.subtitleMode)
        var tracks = TrackPreferences(selection: merged)
        tracks.isClientPick = true
        AppLog(category: "player").notice(
            "device track overrides: audio \(preferences.audioLanguage ?? "-")\(preferences.losslessAudio ? " lossless" : "") -> \(merged.audio?.streamIndex ?? -1), "
            + "subtitles \(preferences.subtitleMode) \(preferences.subtitleLanguage ?? "-") -> \(merged.subtitle?.streamIndex ?? -1) "
            + "(server audio \(selection?.audio?.streamIndex ?? -1), subtitle \(selection?.subtitle?.streamIndex ?? -1))")
        return tracks
    }

    /// A library file's tracks: the profile's languages, under Settings › Playback's overrides,
    /// choosing from the file's own streams as the server's selector would.
    @MainActor
    static func devicePick(audio: [ClientTrackSelector.Stream], subtitles: [ClientTrackSelector.Stream]) -> TrackPreferences {
        let preferences = devicePreferences(over: nil)
        var tracks = TrackPreferences(selection: ClientTrackSelector.select(audio: audio, subtitles: subtitles,
                                                                            preferences: preferences))
        tracks.isClientPick = true
        AppLog(category: "player").notice(
            "library tracks: audio \(preferences.audioLanguage ?? "-") -> \(tracks.audio?.streamIndex ?? -1), "
            + "subtitles \(preferences.subtitleMode) \(preferences.subtitleLanguage ?? "-") -> \(tracks.subtitle?.streamIndex ?? -1)")
        return tracks
    }

    /// The languages to pick with: this device's overrides, else the server's `selection`, else
    /// the profile's values.
    @MainActor
    private static func devicePreferences(over selection: TrackSelection?) -> ClientTrackSelector.Preferences {
        let store = TrackSettingsStore.shared
        let server = store.server
        var allowed = server.allowedLanguages
        // An explicit audio language is honoured even if the profile's list leaves it out.
        if let audio = store.audioLanguage, !allowed.contains(where: { TrackPreferences.sameLanguage($0, audio) }), !allowed.isEmpty {
            allowed.insert(audio, at: 0)
        }
        return ClientTrackSelector.Preferences(
            audioLanguage: store.audioLanguage ?? selection?.audioLanguage ?? server.audioLanguage,
            allowedLanguages: allowed,
            subtitleLanguage: store.subtitleLanguage ?? selection?.subtitleLanguage ?? server.subtitleLanguage,
            subtitleMode: store.subtitleMode ?? selection?.subtitleMode ?? server.subtitleMode ?? "off",
            losslessAudio: store.losslessAudio)
    }

    /// The overrides against a prequeue's track lists, before the engine loads (so the hardware
    /// route starts on the right audio). nil without lists or overrides.
    @MainActor
    static func overridden(_ status: PrequeueStatus) -> TrackPreferences? {
        guard let audio = status.audioTracks, let subtitles = status.subtitleTracks else { return nil }
        return overridden(
            status.trackSelection,
            audio: audio.map { .init(index: $0.index, language: $0.language, title: $0.title ?? "", codec: $0.codec ?? "", forced: false) },
            subtitles: subtitles.map {
                .init(index: $0.absoluteIndex ?? $0.index, language: $0.language, title: $0.title ?? "",
                      codec: $0.codec ?? "", forced: $0.forced ?? false)
            })
    }
}

extension TrackInfo {
    /// Row title in the audio menu: the language, as the stock menu shows it.
    var audioMenuTitle: String {
        if let code = language, let name = Locale.current.localizedString(forLanguageCode: code) {
            return name
        }
        return name.isEmpty ? "Track \(id)" : name
    }

    /// Second line: format, channels and flags ("FLAC 5.1 · Atmos · Commentary").
    var audioMenuDetail: String {
        var format = codec.uppercased()
            .replacingOccurrences(of: "EAC3", with: "E-AC-3")
            .replacingOccurrences(of: "AC3", with: "AC-3")
            .replacingOccurrences(of: "TRUEHD", with: "TrueHD")
        switch channels {
        case 8: format += " 7.1"
        case 6: format += " 5.1"
        case 2: format += " Stereo"
        case 1: format += " Mono"
        default: break
        }
        var parts = [format]
        if isAtmos || (profile?.contains("Atmos") ?? false) { parts.append("Atmos") }
        if isCommentary {
            parts.append("Commentary")
        } else if !name.isEmpty, name != audioMenuTitle, !name.lowercased().contains(codec.lowercased()) {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    /// Row title in the subtitle menu: the language, or the track's name when it has none.
    var subtitleMenuTitle: String {
        if let code = language, let name = Locale.current.localizedString(forLanguageCode: code) {
            return name
        }
        return name.isEmpty ? "Track \(id)" : name
    }

    /// Second line: flags, the track's own name when it adds something, and the format
    /// ("SDH · PGS", "Forced · SRT").
    var subtitleMenuDetail: String {
        var parts: [String] = []
        if isForced { parts.append(String(localized: "Forced")) }
        if isHearingImpaired { parts.append("SDH") }
        if isCommentary { parts.append(String(localized: "Commentary")) }
        if !name.isEmpty, name != subtitleMenuTitle, !parts.contains(where: { name.localizedCaseInsensitiveContains($0) }) {
            parts.append(name)
        }
        parts.append(Self.subtitleFormat(codec))
        return parts.joined(separator: " · ")
    }

    private static func subtitleFormat(_ codec: String) -> String {
        switch codec.lowercased() {
        case "subrip", "srt": "SRT"
        case "ass", "ssa": "ASS"
        case "webvtt": "WebVTT"
        case "mov_text": "Text"
        case "pgssub", "hdmv_pgs_subtitle": "PGS"
        case "dvdsub", "dvd_subtitle": "VobSub"
        case "dvbsub", "dvb_subtitle": "DVB"
        case "eia_608", "eia_708", "cea708", "cea_708": "CC"
        default: codec.uppercased()
        }
    }
}
