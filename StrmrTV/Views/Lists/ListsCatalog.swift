import Foundation

/// The Lists tab's rows that come from the profile's stores, shared by the TV's `ListsView`
/// and the phone's: the personal tiles, streaming services, connected lists, collection
/// hubs and "Because you watched" seeds.
@MainActor
struct ListsCatalog {
    let store: CustomListsStore
    let watchlist: WatchlistStore
    let titles: TitleStateStore
    let listShelves: ListShelvesStore

    /// The server's charts, in the Lists tab's order.
    static let charts: [BrowseList] = [
        .topTen(nil), .topTen(.movies), .topTen(.shows), .trending(.movies), .trending(.shows), .popularOnServer,
    ]

    /// Continue Watching (when there is any), Set Aside, Watchlist, Permanent Prequeue, Hidden.
    var personalTiles: [TileSpec] {
        var tiles: [TileSpec] = []
        let continueWatching = titles.continueWatching
        if !continueWatching.isEmpty {
            tiles.append(TileSpec(.continueWatching, count: continueWatching.count,
                                  art: TileArt(posters: continueWatching.prefix(4).compactMap { $0.textPosterUrl ?? $0.posterUrl },
                                               backdrops: continueWatching.prefix(4).compactMap(\.backdropUrl))))
        }
        if let setAside = store.lists?.first(where: \.isSetAside) {
            tiles.append(TileSpec(.custom(id: setAside.id, name: setAside.name), count: setAside.itemCount))
        }
        tiles.append(TileSpec(.watchlist, count: watchlist.isLoaded ? watchlist.items.count : nil))
        tiles.append(TileSpec(.permanentPrequeue))
        // Where hidden titles can be seen and restored (there is none in the Expo app).
        if !titles.hidden.isEmpty {
            tiles.append(TileSpec(.hidden, count: titles.hidden.count,
                                  art: TileArt(posters: titles.hidden.prefix(4).compactMap(\.posterUrl),
                                               backdrops: titles.hidden.prefix(4).compactMap(\.backdropUrl))))
        }
        return tiles
    }

    /// The profile's own lists, Set Aside left out (it is a personal tile); nil while loading.
    var customTiles: [TileSpec]? {
        store.lists.map { lists in
            lists.filter { !$0.isSetAside }.map { TileSpec(.custom(id: $0.id, name: $0.name), count: $0.itemCount) }
        }
    }

    var shelves: [ShelfConfig] { listShelves.shelves ?? [] }

    var services: [StreamingService] {
        StreamingService.resolved(shelves.first { $0.id == "streaming-services" }?.streamingServices)
    }

    /// Lists configured as home shelves (MDBList, Trakt, Stremio…).
    var connectedTiles: [TileSpec] {
        shelves.compactMap { shelf in shelf.remoteQuery.flatMap { _ in shelf.browseList.map { TileSpec($0) } } }
    }

    /// Collection hub shelves: each card opens another shelf's list, with the card's own art.
    var hubs: [(title: String, tiles: [TileSpec])] {
        let byID = Dictionary(shelves.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return shelves.filter { $0.type == "collection-hub" }.compactMap { hub in
            let tiles = (hub.collectionItems ?? [])
                .filter { $0.enabled != false }
                .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
                .compactMap { item -> TileSpec? in
                    guard let source = item.sourceShelfId.flatMap({ byID[$0] }), let list = source.browseList else { return nil }
                    let art = item.heroArtUrl.map { TileArt(backdrops: [$0]) }
                    return TileSpec(list, title: item.name, art: art, logo: art == nil ? item.logoUrl : nil)
                }
            return tiles.isEmpty ? nil : (hub.title, tiles)
        }
    }

    /// "Because you watched": up to three movies and three shows from Continue Watching,
    /// alternating, each with its own backdrop.
    var seeds: [BrowseList] {
        var seen = Set<String>()
        let candidates = titles.continueWatching.compactMap { item -> BrowseList? in
            guard let tmdb = item.externalIds?["tmdb"], !tmdb.isEmpty, seen.insert(tmdb).inserted else { return nil }
            return .similar(tmdbID: tmdb, kind: item.isMovie ? .movies : .shows, seed: item.seriesTitle, backdrop: item.backdropUrl)
        }
        let movies = candidates.filter { if case .similar(_, .movies, _, _) = $0 { true } else { false } }.prefix(3)
        let shows = candidates.filter { if case .similar(_, .shows, _, _) = $0 { true } else { false } }.prefix(3)
        return (0..<max(movies.count, shows.count)).flatMap { i in
            [i < movies.count ? movies[movies.startIndex + i] : nil, i < shows.count ? shows[shows.startIndex + i] : nil].compactMap { $0 }
        }
    }

    /// "Genres" under a single kind; "Movie Genres" / "Show Genres" when All shows both.
    static func rowTitle(_ title: String, _ rowKind: BrowseKind, chosen: BrowseKind?) -> String {
        guard chosen == nil else { return title }
        return rowKind == .movies ? String(localized: "Movie \(title)") : String(localized: "Show \(title)")
    }
}
