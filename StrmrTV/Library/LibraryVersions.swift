import Foundation

/// One playable copy of a movie or episode: a file in a local, Plex or Jellyfin library.
struct LibraryVersion: Hashable, Identifiable, Sendable {
    let item: LibraryItem
    let libraryName: String

    var id: String { item.id }
    var source: LibrarySource { LibrarySource(item.sourceType) }

    /// "Plex · Films".
    var origin: String { "\(source.label) · \(libraryName)" }

    /// "4K · HEVC · HDR10" from the file's probe, else the server's version name, else the file.
    var quality: String {
        let parts = [resolution, codec, hdr].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        if let label = item.versionLabel, !label.isEmpty { return label }
        return item.fileName ?? String(localized: "Library File")
    }

    /// "21.1 GB · 26 Mbps".
    var size: String? {
        guard let bytes = item.sizeBytes, bytes > 0 else { return nil }
        var parts = [ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)]
        if let seconds = item.probe?.durationSeconds, seconds > 0 {
            let mbps: Double = Double(bytes) * 8 / seconds / 1_000_000
            parts.append("\(Int(mbps.rounded())) Mbps")
        }
        return parts.joined(separator: " · ")
    }

    /// The release name, for the player's Switch Source list.
    var releaseName: String { item.fileName ?? quality }

    /// Size class from the frame, by width first: a 2.39:1 4K file is 3840×1608.
    var resolution: String? {
        let width = item.probe?.width ?? 0, height = item.probe?.height ?? 0
        if width >= 3200 || height >= 1800 { return "4K" }
        if width >= 1800 || height >= 1000 { return "1080p" }
        if width >= 1200 || height >= 700 { return "720p" }
        return height > 0 ? "\(height)p" : nil
    }

    private var codec: String? {
        switch item.probe?.videoCodec?.lowercased() {
        case nil, "": nil
        case "hevc", "h265": "HEVC"
        case "h264", "avc", "avc1": "H.264"
        case let other?: other.uppercased()
        }
    }

    private var hdr: String? {
        guard let raw = item.probe?.hdrFormat?.lowercased(), !raw.isEmpty else { return nil }
        if raw.contains("dolby") || raw.contains("dovi") || raw == "dv" { return "Dolby Vision" }
        if raw.contains("10+") || raw.contains("10plus") { return "HDR10+" }
        if raw.contains("hlg") { return "HLG" }
        if raw.contains("hdr") || raw.contains("pq") { return "HDR10" }
        return raw.uppercased()
    }

    /// Better copies sort first: more pixels, then HDR, then the larger file.
    fileprivate static func isBetter(_ a: LibraryVersion, than b: LibraryVersion) -> Bool {
        let pixels = { (v: LibraryVersion) in (v.item.probe?.width ?? 0) * (v.item.probe?.height ?? 0) }
        if pixels(a) != pixels(b) { return pixels(a) > pixels(b) }
        if (a.hdr != nil) != (b.hdr != nil) { return a.hdr != nil }
        return (a.item.sizeBytes ?? 0) > (b.item.sizeBytes ?? 0)
    }
}

/// A title's copies in the profile's libraries, from `/api/library/matches` or a library
/// group: a movie's versions, or a series' episodes by season and episode number (the
/// library's numbering, as the Expo app maps them). Best copy first.
struct LibraryVersions: Hashable, Sendable {
    struct Key: Hashable, Sendable {
        let season: Int
        let episode: Int
    }

    private(set) var movie: [LibraryVersion] = []
    private(set) var episodes: [Key: [LibraryVersion]] = [:]

    init(matches: [LibraryMatch]) {
        for match in matches { add(match.group, libraryName: match.libraryName) }
        sort()
    }

    init(group: LibraryGroup, libraryName: String) {
        add(group, libraryName: libraryName)
        sort()
    }

    var isEmpty: Bool { movie.isEmpty && episodes.isEmpty }

    /// A movie's versions (no episode), or one episode's copies.
    func versions(season: Int?, episode: Int?) -> [LibraryVersion] {
        guard let season, let episode else { return movie }
        return episodes[Key(season: season, episode: episode)] ?? []
    }

    func best(season: Int?, episode: Int?) -> LibraryVersion? {
        versions(season: season, episode: episode).first
    }

    private mutating func add(_ group: LibraryGroup, libraryName: String) {
        for item in group.items ?? [] where !movie.contains(where: { $0.id == item.id }) {
            movie.append(LibraryVersion(item: item, libraryName: libraryName))
        }
        for season in group.seasons ?? [] {
            for episode in season.episodes {
                let key = Key(season: season.seasonNumber, episode: episode.episodeNumber)
                for item in episode.items where !(episodes[key] ?? []).contains(where: { $0.id == item.id }) {
                    episodes[key, default: []].append(LibraryVersion(item: item, libraryName: libraryName))
                }
            }
        }
    }

    private mutating func sort() {
        movie.sort(by: LibraryVersion.isBetter)
        for key in episodes.keys { episodes[key]?.sort(by: LibraryVersion.isBetter) }
    }
}
