import Foundation

/// The in-player Switch Source menu's model: the ranked sources for what is
/// playing (the Expo player's `sourceOptions`, without automatic migration), the current one
/// marked, and the audio / subtitle languages carried onto the chosen source.
enum SourceSwitch {
    /// What the player is playing: the source picked by hand, or the release the prequeue chose.
    struct Current: Equatable {
        var guid: String?
        var releaseName: String?
        var streamPath: String?
        /// Where the stream comes from, for the player's Stream tab ("Debrid · Real-Debrid").
        var origin: String?
    }

    /// One row of the menu.
    struct Option: Equatable {
        /// nil for the synthetic row standing for a current source the search didn't return.
        let resultIndex: Int?
        let title: String
        let detail: String
        let isCurrent: Bool
    }

    /// The search query the manual source picker uses ("Name S01E02", or "Name 2024").
    static func query(name: String, year: Int?, episode: (season: Int, episode: Int)?) -> String {
        SourceSearch.query(name: name, year: year, episode: episode)
    }

    /// The rows, in the source picker's order (`SourceSearch.ordered`), with the current
    /// source marked. A current source missing from the results leads as its own row (Expo's
    /// `createCurrentSourceMigrationContext`).
    static func options(_ results: [SourceResult], health: [Int: SourceHealth], current: Current) -> [Option] {
        let results = SourceSearch.ordered(results)
        let currentIndex = results.firstIndex { matches($0, current) }
        var rows = results.enumerated().map { position, result in
            Option(resultIndex: result.index, title: releaseName(result),
                   detail: detail(result, health: health[result.index] ?? result.health),
                   isCurrent: position == currentIndex)
        }
        if currentIndex == nil {
            let name = current.releaseName ?? current.streamPath.map { ($0 as NSString).lastPathComponent }
            rows.insert(Option(resultIndex: nil, title: name ?? String(localized: "Current source"),
                               detail: String(localized: "Playing now"), isCurrent: true), at: 0)
        }
        return rows
    }

    /// Same guid, else the same release name (the prequeue's `displayName`), else the stream
    /// path naming the release's folder or file.
    static func matches(_ result: SourceResult, _ current: Current) -> Bool {
        if let guid = current.guid, !guid.isEmpty, result.id == guid { return true }
        let names = Set([result.title, releaseName(result)].map(normalized).filter { !$0.isEmpty })
        if let release = current.releaseName.map(normalized), !release.isEmpty, names.contains(release) { return true }
        if let path = current.streamPath?.removingPercentEncoding.map(normalized) {
            return names.contains { $0.count >= 8 && path.contains($0) }
        }
        return false
    }

    private static func normalized(_ name: String) -> String {
        var s = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for ext in [".mkv", ".mp4", ".m4v", ".avi", ".ts"] where s.hasSuffix(ext) { s.removeLast(ext.count) }
        return s
    }

    /// The release name: the first line of the scraper's raw title when there is one.
    static func releaseName(_ result: SourceResult) -> String {
        (result.attributes["raw_title"] ?? result.title).components(separatedBy: "\n").first ?? result.title
    }

    /// "4K · DV · 18.2 GB · Usenet · Healthy": resolution / HDR, size, provider, then the
    /// cache / health state when known.
    static func detail(_ result: SourceResult, health: SourceHealth?) -> String {
        let attrs = result.attributes
        var parts: [String] = []
        if let res = attrs["resolution"], !res.isEmpty { parts.append(res == "2160p" ? "4K" : res) }
        if attrs["hasDV"] == "true" { parts.append("DV") }
        if let hdr = attrs["hdr"], hdr.contains("HDR10+") { parts.append("HDR10+") } else if let hdr = attrs["hdr"], hdr.contains("HDR") { parts.append("HDR") }
        if result.sizeBytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file)) }
        let provider = result.serviceType.lowercased() == "usenet" ? "Usenet" : (attrs["tracker"] ?? result.indexer)
        if !provider.isEmpty { parts.append(provider) }
        if let state = health.flatMap(healthLabel) { parts.append(state) }
        return parts.joined(separator: " · ")
    }

    static func healthLabel(_ health: SourceHealth) -> String? {
        switch health.state {
        case "cached": String(localized: "Cached")
        case "not_cached": String(localized: "Not Cached")
        case "healthy": String(localized: "Healthy")
        case "unhealthy": String(localized: "Unhealthy")
        case "pending": String(localized: "Checking…")
        default: nil
        }
    }
}

/// The languages carried from one source to the next: track ids are local to a file, so the
/// new source's tracks are picked by language (as Expo's migration re-applies preferences).
struct TrackCarry: Equatable {
    enum Subtitle: Equatable {
        case off
        case language(String, forced: Bool)
        /// An online subtitle, or nothing known: the new source picks as usual.
        case unchanged
    }

    /// The parts of an engine track the carry looks at.
    struct Track: Equatable {
        let id: Int
        let language: String?
        var isForced = false
        var isCommentary = false
    }

    let audioLanguage: String?
    let subtitle: Subtitle

    /// The new source's audio track in the carried language (not commentary, first by stream).
    func audioTrackID(in tracks: [Track]) -> Int? {
        guard let audioLanguage else { return nil }
        let same = tracks.filter { TrackPreferences.sameLanguage($0.language, audioLanguage) }.sorted { $0.id < $1.id }
        return (same.first { !$0.isCommentary } ?? same.first)?.id
    }

    /// The subtitle to select: `.some(nil)` is Off, nil leaves the new source's own pick.
    func subtitleTrackID(in tracks: [Track]) -> Int?? {
        switch subtitle {
        case .off: return .some(nil)
        case .unchanged: return nil
        case let .language(language, forced):
            let same = tracks.filter { TrackPreferences.sameLanguage($0.language, language) }.sorted { $0.id < $1.id }
            guard let pick = same.first(where: { $0.isForced == forced }) ?? same.first else { return nil }
            return .some(pick.id)
        }
    }
}
