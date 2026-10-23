import Foundation

/// Seek-preview thumbnails generated (or fetched from Seekr) by the backend:
/// `POST /api/video/thumbnails/start`, `GET /api/video/thumbnails/status` and the
/// images under `/api/video/thumbnails/image/{key}/{file}`.
struct VideoThumbnailStatus: Decodable {
    struct Item: Decodable, Equatable {
        let timeSec: Double
        let url: String
    }

    let key: String?
    /// `pending`, `generating`, `ready`, `failed` or `disabled`.
    let status: String
    let thumbnails: [Item]?
}

extension APIClient {
    /// Whether the server admin has seek-preview thumbnails turned on
    /// (`settings.playback.thumbnails.enabled`, the flag the Expo player honours).
    func previewThumbnailsEnabled() async -> Bool {
        struct Settings: Decodable {
            struct Playback: Decodable {
                struct Thumbnails: Decodable { let enabled: Bool? }
                let thumbnails: Thumbnails?
            }
            let playback: Playback?
        }
        guard let settings: Settings = try? await send("GET", "/api/settings", promptOnLock: false, timeout: 10) else {
            return false
        }
        return settings.playback?.thumbnails?.enabled ?? false
    }

    struct ThumbnailStartOptions {
        var seekrOnly = false
        var imdbID: String?
        var tmdbID: String?
        /// `movie` or `episode` (what the backend's Seekr lookup accepts).
        var mediaType: String
        var season: Int?
        var episode: Int?
        var hdr = false
        var dolbyVision = false
        var dvProfile: String?
        var chapterTimes: [Double] = []
    }

    func startVideoThumbnails(path: String, duration: Double, interval: Int = 60,
                              options: ThumbnailStartOptions) async throws -> VideoThumbnailStatus {
        var items = [URLQueryItem(name: "path", value: path),
                     URLQueryItem(name: "duration", value: String(format: "%.2f", duration)),
                     URLQueryItem(name: "interval", value: String(interval))]
        if options.hdr { items.append(.init(name: "hdr", value: "1")) }
        if options.dolbyVision { items.append(.init(name: "dv", value: "1")) }
        if let p = options.dvProfile { items.append(.init(name: "dvProfile", value: p)) }
        if options.seekrOnly { items.append(.init(name: "seekrOnly", value: "1")) }
        if let v = options.imdbID { items.append(.init(name: "imdbId", value: v)) }
        if let v = options.tmdbID { items.append(.init(name: "tmdbId", value: v)) }
        items.append(.init(name: "mediaType", value: options.mediaType))
        if let v = options.season { items.append(.init(name: "season", value: String(v))) }
        if let v = options.episode { items.append(.init(name: "episode", value: String(v))) }
        for t in options.chapterTimes where t.isFinite && t >= 0 {
            items.append(.init(name: "chapter", value: String(format: "%.1f", t)))
        }
        return try await sendThumbnails("POST", items: items)
    }

    func videoThumbnailsStatus(path: String) async throws -> VideoThumbnailStatus {
        try await sendThumbnails("GET", items: [URLQueryItem(name: "path", value: path)], status: true)
    }

    private func sendThumbnails(_ method: String, items: [URLQueryItem], status: Bool = false) async throws -> VideoThumbnailStatus {
        let endpoint = status ? "/api/video/thumbnails/status" : "/api/video/thumbnails/start"
        // `chapter` repeats, so the query is pre-encoded rather than a dictionary.
        let query = items.map { "\(Self.segment($0.name))=\(Self.segment($0.value ?? ""))" }.joined(separator: "&")
        let data = try await sendRaw(method, endpoint, promptOnLock: false, timeout: 60, encodedQuery: query)
        return try decoder.decode(VideoThumbnailStatus.self, from: data)
    }

    /// Absolute URL for a thumbnail the status lists (server-relative `/api/...`, possibly
    /// with a `token=` query when one was sent; none is, auth rides in headers).
    func thumbnailImageURL(_ raw: String) -> URL? {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        let path = raw.split(separator: "?", maxSplits: 1).first.map(String.init) ?? raw
        guard path.hasPrefix("/") else { return nil }
        return url(path)
    }
}
