import Foundation

/// One channel from `/api/live/channels`. With more than one source configured, `id` is
/// `{sourceId}:{rawId}`; favorites and hidden channels are stored by `id`.
struct LiveChannel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// The provider URL; `/api/live/hls/start` tunes it.
    let url: String
    let logo: String?
    /// The channel's category.
    let group: String?
    /// The EPG key; channels without one have no guide data.
    let tvgId: String?
    let tvgName: String?
    let sourceId: String?
    let sourceName: String?
    /// Provider-local id, sent as `channelId` when tuning.
    let playbackId: String?
    /// The stream picked under Choose Source, for a channel that is a Stremio addon's stream
    /// list; sent as `stremioStreamIndex` when tuning (nil lets the server pick).
    var stremioStreamIndex: Int? = nil

    /// A Stremio addon stream resource (`…/stream/….json`), which can list several streams to
    /// choose from (Expo `isStremioStreamResourceUrl`).
    var hasStremioSources: Bool {
        let path = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        return url.hasPrefix("http") && path.contains("/stream/") && path.hasSuffix(".json")
    }

    /// The key its EPG data is filed under (`tvgId`, else the channel id, as the Expo guide does).
    var guideKey: String { tvgId.flatMap { $0.isEmpty ? nil : $0 } ?? id }

    /// The logo as a loadable image. Playlists often link GitHub's HTML page for an image
    /// (`github.com/…/blob/…`), which is rewritten to the raw file.
    var logoURL: URL? {
        guard var logo, !logo.isEmpty else { return nil }
        if logo.hasPrefix("https://github.com/"), logo.contains("/blob/") {
            logo = logo.replacingOccurrences(of: "https://github.com/", with: "https://raw.githubusercontent.com/")
                .replacingOccurrences(of: "/blob/", with: "/")
        }
        return URL(string: logo)
    }
}

/// One stream of a Stremio channel (`GET /api/live/stremio/streams`), by its index in the addon's list.
struct LiveStremioStream: Decodable, Hashable, Identifiable {
    let index: Int
    let label: String
    let name: String?
    let title: String?
    let description: String?

    var id: Int { index }
}

struct LiveSource: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
}

/// `POST /api/live/channels`: one page of the filtered list, favorites first.
struct LiveChannelsPage: Decodable {
    let channels: [LiveChannel]
    let total: Int
    let hasMore: Bool
    let availableCategories: [String]?
    let sources: [LiveSource]?
}

/// A programme from the EPG; the server has already applied the profile's time offset.
struct EPGProgram: Decodable, Hashable {
    let title: String
    let description: String?
    let start: Date
    var stop: Date
    let icon: String?
    let categories: [String]?
    let episode: String?

    private enum CodingKeys: String, CodingKey { case title, description, start, stop, icon, categories, episode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        start = try Self.date(c, .start)
        stop = try Self.date(c, .stop)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        categories = try c.decodeIfPresent([String].self, forKey: .categories)
        episode = try c.decodeIfPresent(String.self, forKey: .episode)
    }

    /// RFC 3339, with or without fractional seconds.
    private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date {
        let text = try c.decode(String.self, forKey: key)
        if let date = try? Date(text, strategy: .iso8601) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not an RFC 3339 date: \(text)")
    }

    func progress(at now: Date) -> Double {
        let length = stop.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(start) / length, 0), 1)
    }

    func isAiring(at now: Date) -> Bool { start <= now && now < stop }
}

/// `POST /api/live/epg/now`: one entry per requested key, in request order.
struct EPGNowPlaying: Decodable {
    let channelId: String
    let current: EPGProgram?
    let next: EPGProgram?
}

struct EPGStatus: Decodable {
    /// Already resolved with the profile's override.
    let enabled: Bool
}

/// `GET /api/live/hls/start`: a direct stream, or a server HLS session to keep alive.
struct LiveStart: Decodable {
    let streamUrl: String?
    let isDirect: Bool?
    let sessionId: String?
    let playlistUrl: String?
}
