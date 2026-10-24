import Foundation

/// The Lists tab: the profile's custom lists and the server's discovery lists (Top 10,
/// popular on this server, TMDB genres and decades), all read through `/display-list`,
/// which sorts, filters (hidden titles, kids ratings, release visibility) and pages them.
extension APIClient {
    /// `GET /api/users/{id}/custom-lists`, in the server's order.
    func customLists() async throws -> [CustomList] {
        try await send("GET", "\(profilePath)/custom-lists")
    }

    @discardableResult
    func createCustomList(name: String) async throws -> CustomList {
        try await send("POST", "\(profilePath)/custom-lists", jsonObject: ["name": name])
    }

    @discardableResult
    func renameCustomList(id: String, name: String) async throws -> CustomList {
        try await send("PATCH", "\(profilePath)/custom-lists/\(Self.segment(id))", jsonObject: ["name": name])
    }

    func deleteCustomList(id: String) async throws {
        try await sendRaw("DELETE", "\(profilePath)/custom-lists/\(Self.segment(id))")
    }

    /// Every item of a list, unsorted and unfiltered (for membership checks).
    func customListItems(id: String) async throws -> [WatchlistItem] {
        try await send("GET", "\(profilePath)/custom-lists/\(Self.segment(id))/items")
    }

    /// Adds a title; the server matches it against stored items by any shared ID.
    @discardableResult
    func addToCustomList(id: String, _ upsert: WatchlistUpsert) async throws -> WatchlistItem {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(upsert)) as? [String: Any] ?? [:]
        return try await send("POST", "\(profilePath)/custom-lists/\(Self.segment(id))/items", jsonObject: body)
    }

    /// Removes an item by its stored media type and ID; a 404 (already gone) counts as success.
    func removeFromCustomList(id: String, mediaType: String, itemID: String) async throws {
        do {
            try await sendRaw("DELETE", "\(profilePath)/custom-lists/\(Self.segment(id))/items/\(Self.segment(mediaType))/\(Self.segment(itemID))")
        } catch let error as APIError where error.statusCode == 404 {
            return
        }
    }

    /// One page of a list, as titles whatever the source's item shape, sorted and
    /// filtered server-side by `options`. `extra` adds query parameters (Home's
    /// `hideWatched` / `hideUnreleased`). With a `phase`, a remote list that pages
    /// progressively reads only enough of its source to fill the page (see `ShelfPhase`);
    /// other lists ignore it.
    func browsePage(_ list: BrowseList, options: BrowseOptions = BrowseOptions(), limit: Int, offset: Int = 0,
                    extra: [String: String] = [:], phase: ShelfPhase? = nil) async throws -> BrowsePage {
        if case let .library(library) = list {
            return try await libraryPage(library, options: options, limit: limit, offset: offset)
        }
        let serviceLists = list.serviceLists(part: options.part).count
        if serviceLists > 1 {
            return try await mergedServicePage(list, options: options, sources: serviceLists, limit: limit, offset: offset, extra: extra)
        }
        var query = list.query.merging(options.query(for: list)) { _, new in new }.merging(extra) { _, new in new }
        query["limit"] = String(limit)
        query["offset"] = String(offset)
        if let phase, list.loadsProgressively { query.merge(phase.query) { _, new in new } }
        let path = "\(profilePath)/display-list"
        // An AI answer can take well over the usual 30 s the first time it is asked. A remote
        // list sorted or filtered cold makes the server enrich the whole list first (a 200-title
        // MDBList took ~35 s), so these get the Expo client's 60 s. A long list's complete pass
        // on a cold server can take longer still; it runs behind cards already showing.
        let timeout: TimeInterval = query["source"] == "custom-ai" ? 120
            : phase == .complete && list.loadsProgressively ? 180 : 60
        switch list.itemShape {
        case .item:
            let page: DisplayListPage<WatchlistItem> = try await send("GET", path, query: query)
            return BrowsePage(entries: page.items.map(BrowseEntry.item), total: page.listTotal,
                              genres: page.genres ?? [], letters: page.alphabetBuckets ?? [])
        case .ranked:
            let page: DisplayListPage<TrendingItem> = try await send("GET", path, query: query, timeout: timeout)
            return BrowsePage(entries: page.items.map { .title($0.title) }, total: page.listTotal,
                              genres: page.genres ?? [], letters: page.alphabetBuckets ?? [])
        case .title:
            let page: DisplayListPage<Title> = try await send("GET", path, query: query)
            return BrowsePage(entries: page.items.map(BrowseEntry.title), total: page.listTotal,
                              genres: page.genres ?? [], letters: page.alphabetBuckets ?? [])
        }
    }
}
