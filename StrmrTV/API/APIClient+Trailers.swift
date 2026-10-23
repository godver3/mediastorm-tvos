import Foundation

/// One trailer from `/api/metadata/trailers` or the details bundle's `trailers`.
struct Trailer: Decodable, Equatable, Sendable {
    let name: String
    let url: String
    let site: String?
    let type: String?
}

/// The server ranks the candidates (official trailers, English, resolution) into
/// `primaryTrailer`; the Expo app plays that, else the first.
struct TrailerList: Decodable, Sendable {
    let primaryTrailer: Trailer?
    let trailers: [Trailer]?

    var primary: Trailer? { primaryTrailer ?? trailers?.first }
}

extension APIClient {
    /// A playable URL for `trailer`, as the Expo TV app gets one: a YouTube trailer is
    /// downloaded by the server (`POST /api/metadata/trailers/prequeue`, polled every second
    /// until ready) and served as an H.264 / AAC MP4 with range support; any other URL is
    /// played as it is. Nil when the download fails or takes over two minutes.
    ///
    /// A downloaded file the client never fetches is deleted about a minute after it is ready,
    /// so call this again right before a late play rather than keeping the URL: the server
    /// returns the same ID, and re-downloads only what it already cleaned up.
    func trailerURL(for trailer: Trailer) async -> URL? {
        guard let source = URL(string: trailer.url) else { return nil }
        guard Self.isYouTube(source) else { return source }
        struct Status: Decodable { let id: String; let status: String; let error: String? }
        do {
            let queued: Status = try await send("POST", "/api/metadata/trailers/prequeue",
                                                jsonObject: ["url": trailer.url], promptOnLock: false, timeout: 15)
            for _ in 0..<120 {
                let status: Status = try await send("GET", "/api/metadata/trailers/prequeue/status",
                                                    query: ["id": queued.id], promptOnLock: false, timeout: 10)
                switch status.status {
                case "ready": return trailerServeURL(id: queued.id)
                case "failed": return nil
                default: try await Task.sleep(for: .seconds(1))
                }
            }
        } catch {}
        return nil
    }

    /// The downloaded file. AVPlayer sends no custom headers, so auth rides in `token=`, which
    /// the server accepts on this route.
    private func trailerServeURL(id: String) -> URL {
        var query = ["id": id]
        if let token { query["token"] = token }
        return url("/api/metadata/trailers/prequeue/serve", query: query)
    }

    /// The hosts the server's prequeue accepts.
    private static func isYouTube(_ url: URL) -> Bool {
        ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "www.youtu.be"]
            .contains(url.host?.lowercased() ?? "")
    }
}
