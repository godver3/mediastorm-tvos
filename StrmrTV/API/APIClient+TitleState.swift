import Foundation

/// Hidden titles and watched keys, as the Expo app's HiddenItemsContext and
/// WatchStatusContext read them.
extension APIClient {
    func hiddenItems() async throws -> [HiddenItem] {
        try await send("GET", "\(profilePath)/hidden-items")
    }

    /// Hides a title from this profile; the server drops it from Home rows and lists.
    @discardableResult
    func hide(_ target: DetailsTarget) async throws -> HiddenItem {
        var body: [String: Any] = ["id": target.titleID, "mediaType": target.isMovie ? "movie" : "series",
                                   "name": target.name]
        if let year = target.year { body["year"] = year }
        if let poster = target.posterURL { body["posterUrl"] = poster }
        if let backdrop = target.backdropURL { body["backdropUrl"] = backdrop }
        if let ids = target.watchlistUpsert.externalIds { body["externalIds"] = ids }
        return try await send("POST", "\(profilePath)/hidden-items", jsonObject: body)
    }

    func unhide(mediaType: String, id: String) async throws {
        try await sendRaw("DELETE", "\(profilePath)/hidden-items/\(Self.segment(mediaType))/\(Self.segment(id))")
    }

    /// Every watched item's identity keys (`movie:tmdb:movie:123`, …), lowercased.
    func watchedKeys() async throws -> Set<String> {
        struct Keys: Decodable { let watched: [String]? }
        let keys: Keys = try await send("GET", "\(profilePath)/history/watched",
                                        query: ["fields": "status", "format": "keys"], timeout: 60)
        return Set((keys.watched ?? []).map { $0.lowercased() })
    }
}
