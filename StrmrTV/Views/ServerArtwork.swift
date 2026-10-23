import Foundation

/// Artwork the server serves itself (`/api/…`: Plex and Jellyfin posters and backdrops through
/// the library API), which needs the app's credentials. Cards carry it as `strmr-server:` URLs,
/// a cache key that stays put whatever the server's address (the iroh proxy's port can change)
/// or token; `ImagePipeline` turns one into an authorized request when it fetches.
enum ServerArtwork {
    static let scheme = "strmr-server"

    /// The card URL for a server-relative path such as "/api/library/items/…/artwork/poster".
    static func url(_ path: String) -> URL? { URL(string: "\(scheme):\(path)") }

    /// The request for a `strmr-server:` URL: the server's current address, the active profile
    /// (the server checks its access to the library) and the media headers (token, profile
    /// unlock, remote-access credential).
    @MainActor
    static func request(for url: URL) -> URLRequest? {
        guard url.scheme == scheme else { return nil }
        let api = APIClient.shared
        var query = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .reduce(into: [String: String]()) { $0[$1.name] = $1.value ?? "" }
        query["profileId"] = api.profileID
        var request = URLRequest(url: api.url(url.path(percentEncoded: true), query: query),
                                 cachePolicy: .returnCacheDataElseLoad)
        for (name, value) in api.mediaHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }
}
