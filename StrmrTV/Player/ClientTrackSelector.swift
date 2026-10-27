import AetherEngine
import Foundation

/// The server's track selector (`backend/services/trackselect`: `Select`, `FindAllowedAudioTrack`,
/// `FindAudioTrack`, `FindSubtitleTrack`) run on this device, for when Settings › Playback
/// overrides the profile's languages or subtitle mode. Keep it in step with the Go code.
enum ClientTrackSelector {
    /// One container stream, from the prequeue's track lists or the engine's.
    struct Stream {
        let index: Int
        let language: String?
        let title: String
        let codec: String
        let forced: Bool
    }

    struct Preferences {
        var audioLanguage: String?
        var allowedLanguages: [String] = []
        var subtitleLanguage: String?
        /// `off`, `forced-only` or `on`.
        var subtitleMode: String
        /// Settings › Playback › Audio Format is Lossless: TrueHD first (`findAudio`).
        var losslessAudio = false
    }

    static func select(audio: [Stream], subtitles: [Stream], preferences p: Preferences) -> TrackSelection {
        let audioIndex = (p.audioLanguage?.isEmpty == false || !p.allowedLanguages.isEmpty)
            ? findAllowedAudio(audio, allowed: p.allowedLanguages, preferred: p.audioLanguage ?? "",
                               lossless: p.losslessAudio) : -1
        let audioPick = describe(audio, audioIndex)
        var subtitlePick: SelectedTrack?
        var textPick: SelectedTrack?
        if p.subtitleMode != "off" {
            let audioLanguage = audioPick?.language ?? p.audioLanguage ?? ""
            let language = p.subtitleLanguage ?? ""
            subtitlePick = describe(subtitles, findSubtitle(subtitles, language: language, mode: p.subtitleMode,
                                                            audioLanguage: audioLanguage))
            if let subtitlePick, isText(subtitlePick.codec ?? "") {
                textPick = subtitlePick
            } else {
                let text = subtitles.filter { isText($0.codec) }
                textPick = describe(subtitles, findSubtitle(text, language: language, mode: p.subtitleMode,
                                                            audioLanguage: audioLanguage))
            }
        }
        return TrackSelection(audio: audioPick, subtitle: subtitlePick, textSubtitle: textPick,
                              audioLanguage: p.audioLanguage, subtitleLanguage: p.subtitleLanguage,
                              subtitleMode: p.subtitleMode)
    }

    // MARK: Audio

    static func findAllowedAudio(_ streams: [Stream], allowed: [String], preferred: String,
                                 lossless: Bool = false) -> Int {
        let allowed = allowed.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !allowed.isEmpty else { return findAudio(streams, preferred: preferred, lossless: lossless) }
        if !preferred.isEmpty, allowed.contains(where: { matches(preferred, "", $0) }) {
            let picked = findAudio(streams, preferred: preferred, lossless: lossless)
            if picked >= 0 { return picked }
        }
        for language in allowed {
            let picked = findAudio(streams, preferred: language, lossless: lossless)
            if picked >= 0 { return picked }
        }
        return -1
    }

    /// E-AC-3, then other direct-play codecs, then anything but TrueHD, then TrueHD; first
    /// without commentary, then with it. `lossless` (Settings › Playback › Audio Format) puts
    /// TrueHD, then DTS / FLAC / PCM (`isLossless`), ahead of that order. A region-tagged
    /// preference (`fr-CA`) first tries that regional dub (`RegionalAudio`).
    static func findAudio(_ streams: [Stream], preferred: String, lossless: Bool = false) -> Int {
        guard !preferred.isEmpty else { return -1 }
        let compatible: Set = ["aac", "ac3", "eac3", "mp3"]
        let losslessClasses: [(Stream) -> Bool] = [{ isTrueHD($0.codec) }, { isLossless($0.codec) }]
        let classes: [(Stream) -> Bool] = (lossless ? losslessClasses : []) + [
            { $0.codec.lowercased() == "eac3" },
            { compatible.contains($0.codec.lowercased()) },
            { !isTrueHD($0.codec) },
            { _ in true },
        ]
        if let variant = RegionalAudio.variant(preferred) {
            for codecClass in classes {
                if let hit = streams.first(where: {
                    matches($0.language ?? "", $0.title, preferred) && codecClass($0) && !isCommentary($0.title)
                        && RegionalAudio.matches(variant, language: $0.language, title: $0.title)
                }) { return hit.index }
            }
        }
        for allowCommentary in [false, true] {
            for codecClass in classes {
                if let hit = streams.first(where: {
                    matches($0.language ?? "", $0.title, preferred) && codecClass($0)
                        && (allowCommentary || !isCommentary($0.title))
                }) { return hit.index }
            }
        }
        return -1
    }

    // MARK: Subtitles

    static func findSubtitle(_ streams: [Stream], language: String, mode: String, audioLanguage: String) -> Int {
        guard mode != "off" else { return -1 }
        let selectable = streams.filter { !isUnsupported($0.codec) }
        guard !selectable.isEmpty else { return -1 }
        if mode == "forced-only" {
            return selectable.first { isForced($0) && matches($0.language ?? "", $0.title, language) }?.index ?? -1
        }
        guard !language.isEmpty else { return -1 }
        let candidates = selectable.filter { !isForced($0) && matches($0.language ?? "", $0.title, language) }
        guard let first = candidates.first else {
            return selectable.first { isForced($0) && matches($0.language ?? "", $0.title, language) }?.index ?? -1
        }
        let title = { (s: Stream) in s.title.lowercased() }
        let sdh = { (s: Stream) in ["sdh", "deaf", "hard of hearing"].contains(where: title(s).contains) }
        let signs = { (s: Stream) in title(s).contains("sign") || title(s).contains("song") }
        let dubtitle = { (s: Stream) in title(s).contains("dubtitle") }
        let full = { (s: Stream) in title(s).contains("full sub") || title(s).trimmingCharacters(in: .whitespaces).isEmpty }
        let sameLanguage = matches(audioLanguage, "", language)
        let order: [(Stream) -> Bool] = [{ sdh($0) && !signs($0) }]
            + (sameLanguage ? [dubtitle, full] : [full, dubtitle])
            + [{ !signs($0) }]
        for rule in order {
            if let hit = candidates.first(where: rule) { return hit.index }
        }
        return first.index
    }

    // MARK: Helpers

    /// `MatchesLanguage`: the stream's language, or a word of its language / title, names the
    /// preferred language (codes and English names alike).
    static func matches(_ language: String, _ title: String, _ preferred: String) -> Bool {
        let pref = preferred.trimmingCharacters(in: .whitespaces).lowercased()
        guard !pref.isEmpty else { return false }
        let lang = language.trimmingCharacters(in: .whitespaces).lowercased()
        if names(lang, pref) { return true }
        let words = (lang + " " + title.lowercased()).split { !("a"..."z").contains($0) }.map(String.init)
        // Two-letter words ("de", "it") are too often ordinary words in a title.
        return words.contains { ($0.count > 2 || $0 == lang) && names($0, pref) }
    }

    private static func names(_ tag: String, _ preferred: String) -> Bool {
        guard !tag.isEmpty else { return false }
        if TrackPreferences.sameLanguage(tag, preferred) { return true }
        let code = TrackPreferences.normalize(preferred)
        let english = Locale(identifier: "en").localizedString(forLanguageCode: code)?.lowercased()
        return tag == english || (TrackPreferences.normalize(tag) == code && tag.count <= 3)
    }

    static func describe(_ streams: [Stream], _ index: Int) -> SelectedTrack? {
        guard index >= 0, let typeIndex = streams.firstIndex(where: { $0.index == index }) else { return nil }
        let stream = streams[typeIndex]
        let same = streams.enumerated().filter { TrackPreferences.sameLanguage($0.element.language, stream.language) }
        return SelectedTrack(streamIndex: stream.index, typeIndex: typeIndex, language: stream.language,
                             languageCode: stream.language, languageIndex: same.filter { $0.offset < typeIndex }.count,
                             languageCount: same.count, codec: stream.codec, title: stream.title,
                             forced: isForced(stream), bitmap: !isText(stream.codec))
    }

    static func isForced(_ s: Stream) -> Bool { s.forced || s.title.lowercased().contains("forced") }
    static func isText(_ codec: String) -> Bool { OnlineSubtitles.isTextCodec(codec) || codec.lowercased() == "vtt" }
    static func isTrueHD(_ codec: String) -> Bool { ["truehd", "mlp"].contains(codec.lowercased()) }
    /// The lossless formats after TrueHD. libav names DTS-HD MA plain `dts`, so DTS counts.
    static func isLossless(_ codec: String) -> Bool {
        let c = codec.lowercased()
        return isTrueHD(c) || c == "dts" || c == "flac" || c == "alac" || c.hasPrefix("pcm")
    }
    static func isUnsupported(_ codec: String) -> Bool {
        let c = codec.lowercased()
        return c.contains("dvd_subtitle") || c == "dvdsub" || c.contains("vobsub") || c.contains("dvd subtitle")
    }

    /// Commentary or audio description ("French (France) AD"): not the main mix.
    static func isCommentary(_ title: String) -> Bool {
        let t = title.lowercased()
        return ["commentary", "isolated score", "music only", "score only", "audio description", "audiodescription",
                "audio-description", "descriptive audio", "described video"].contains(where: t.contains)
            || t.split { !("a"..."z").contains($0) }.contains("ad")
    }
}

extension ClientTrackSelector.Stream {
    init(_ track: TrackInfo) {
        self.init(index: track.id, language: track.language, title: track.name, codec: track.codec, forced: track.isForced)
    }
}
