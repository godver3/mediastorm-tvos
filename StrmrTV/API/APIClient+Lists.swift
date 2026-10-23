import Foundation

/// Watchlist and discovery rows, served by `/display-list` (sorted, filtered and paged
/// server-side) plus the watchlist write endpoints.
extension APIClient {
    /// The whole watchlist in the server's order (most recently added first).
    func watchlist() async throws -> [WatchlistItem] {
        let page: DisplayListPage<WatchlistItem> = try await send(
            "GET", "/api/users/\(Self.segment(profileID))/display-list", query: ["source": "watchlist"])
        return page.items
    }

    /// Trending titles of one kind (`movie` or `series`).
    func trending(mediaType: String, limit: Int = 20, offset: Int = 0) async throws -> DisplayListPage<TrendingItem> {
        try await send(
            "GET", "/api/users/\(Self.segment(profileID))/display-list",
            query: ["source": "trending", "mediaType": mediaType, "limit": String(limit), "offset": String(offset)])
    }

    @discardableResult
    func addToWatchlist(_ upsert: WatchlistUpsert) async throws -> WatchlistItem {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(upsert)) as? [String: Any] ?? [:]
        return try await send("POST", "/api/users/\(Self.segment(profileID))/watchlist", jsonObject: body)
    }

    /// Removes a title. The server matches any stored ID form; a 404 means it was
    /// already gone, which counts as success.
    func removeFromWatchlist(mediaType: String, id: String) async throws {
        do {
            try await sendRaw("DELETE", "/api/users/\(Self.segment(profileID))/watchlist/\(Self.segment(mediaType))/\(Self.segment(id))")
        } catch let error as APIError where error.statusCode == 404 {
            return
        }
    }
}
