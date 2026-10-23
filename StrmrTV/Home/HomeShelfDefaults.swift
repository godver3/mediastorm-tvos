import Foundation

/// The Expo app's built-in Home shelves (`DEFAULT_HOME_SHELF_CONFIG`) and its
/// `ensureHomeShelfConfig`, which Home views apply to the layout they inherit.
enum HomeShelfDefaults {
    static let shelves: [ShelfConfig] = ([
        ["id": "watch-together", "name": "Watch Together", "enabled": true, "order": -1],
        ["id": "top-ten", "name": "Top 10 Today", "enabled": true, "order": 0],
        ["id": "continue-watching", "name": "Continue Watching", "enabled": true, "order": 1],
        ["id": "watch-something", "name": "Watch Something", "enabled": true, "order": 2],
        ["id": "tonight", "name": "Tonight", "enabled": false, "order": 3],
        ["id": "my-recommended", "name": "My Recommended", "enabled": true, "order": 4],
        ["id": "my-upcoming", "name": "My Upcoming", "enabled": true, "order": 5, "sort": "air-date-asc"],
        ["id": "calendar", "name": "Coming Up", "enabled": true, "order": 6],
        ["id": "my-recently-aired", "name": "My Recently Aired", "enabled": true, "order": 7,
         "calendarSources": recentlyAiredSources],
        ["id": "watchlist", "name": "Your Watchlist", "enabled": true, "order": 8],
        ["id": "trending-movies", "name": "Trending Movies", "enabled": true, "order": 9],
        ["id": "trending-tv", "name": "Trending TV Shows", "enabled": true, "order": 10],
        ["id": "streaming-services", "name": "Streaming Services", "enabled": true, "order": 11],
        ["id": "live-favorites", "name": "Favorite Channels", "enabled": false, "order": 12],
        ["id": "popular-on-server", "name": "Popular on This Server", "enabled": false, "order": 13, "limit": 20,
         "activityWindowDays": 90, "minimumProfiles": 2],
        ["id": "recently-watched", "name": "Recently Watched", "enabled": false, "order": 14, "limit": 20,
         "activityWindowDays": 14, "maxItemsPerProfile": 3],
        ["id": "dashboard", "name": "Dashboard", "enabled": false, "order": 15],
        ["id": "permanent-prequeue", "name": "Permanent Prequeue", "enabled": false, "order": 16],
        ["id": "set-aside", "name": "Set Aside", "enabled": false, "order": 17],
    ] as [[String: Any]]).compactMap(ShelfConfig.make)

    private static let recentlyAiredSources: [String: Bool] = [
        "watchlist": true, "history": false, "trending": false, "topTrending": false, "mdblists": false,
    ]

    /// Fills in the built-in shelves a configured list lacks, each placed after the shelf
    /// it follows in the Expo app (moving the rest down), turns Tonight off and puts Watch
    /// Together first (`ensureHomeShelfConfig`, without simple mode). An empty list is the
    /// defaults.
    static func ensure(_ shelves: [ShelfConfig]) -> [ShelfConfig] {
        if shelves.isEmpty { return Self.shelves }
        var seen = Set<String>()
        var next = shelves.filter { seen.insert($0.id).inserted }
            .map { $0.id == "tonight" && $0.enabled == true ? $0.with(enabled: false) : $0 }

        func has(_ id: String) -> Bool { next.contains { $0.id == id } }
        func order(of id: String) -> Int? { next.first { $0.id == id }.map { $0.order ?? 0 } }
        func after(_ id: String, else fallback: Int) -> Int { order(of: id).map { $0 + 1 } ?? fallback }
        var last: Int { (next.map { $0.order ?? 0 } + [-1]).max()! + 1 }
        func insert(_ fields: [String: Any], at position: Int) {
            next = next.map { shelf in
                var shelf = shelf
                if (shelf.order ?? 0) >= position { shelf.order = (shelf.order ?? 0) + 1 }
                return shelf
            }
            var fields = fields
            fields["order"] = position
            if let shelf = ShelfConfig.make(fields) { next.append(shelf) }
        }

        if !has("my-upcoming") {
            insert(["id": "my-upcoming", "name": "My Upcoming", "enabled": true, "sort": "air-date-asc"],
                   at: after("continue-watching", else: 2))
        } else if next.contains(where: { $0.id == "my-upcoming" && $0.sort == nil }) {
            next = next.map { shelf in
                var shelf = shelf
                if shelf.id == "my-upcoming" { shelf.sort = "air-date-asc" }
                return shelf
            }
        }
        if !has("my-recommended"), !has("gemini-recs") {
            insert(["id": "my-recommended", "name": "My Recommended", "enabled": true],
                   at: after("continue-watching", else: 2))
        }
        if !has("calendar") {
            insert(["id": "calendar", "name": "Coming Up", "enabled": true], at: after("my-upcoming", else: 4))
        }
        if !has("my-recently-aired") {
            insert(["id": "my-recently-aired", "name": "My Recently Aired", "enabled": true,
                    "calendarSources": recentlyAiredSources], at: after("calendar", else: 3))
        }
        if !has("tonight") {
            insert(["id": "tonight", "name": "Tonight", "enabled": false], at: after("continue-watching", else: 2))
        }
        if !has("streaming-services") {
            insert(["id": "streaming-services", "name": "Streaming Services", "enabled": true],
                   at: after("trending-tv", else: last))
        }
        if !has("live-favorites") {
            insert(["id": "live-favorites", "name": "Favorite Channels", "enabled": false],
                   at: after("streaming-services", else: last))
        }
        if !has("dashboard") {
            insert(["id": "dashboard", "name": "Dashboard", "enabled": false], at: after("recently-watched", else: last))
        }
        if !has("permanent-prequeue") {
            insert(["id": "permanent-prequeue", "name": "Permanent Prequeue", "enabled": false],
                   at: after("dashboard", else: last))
        }
        if !has("set-aside") {
            insert(["id": "set-aside", "name": "Set Aside", "enabled": false], at: after("permanent-prequeue", else: last))
        }
        if !has("watch-something") {
            insert(["id": "watch-something", "name": "Watch Something", "enabled": true],
                   at: after("continue-watching", else: 2))
        }
        let watchTogether = ShelfConfig.make(["id": "watch-together", "name": "Watch Together", "enabled": true, "order": -1])
        return (watchTogether.map { [$0] } ?? []) + next.filter { $0.id != "watch-together" }
    }
}
