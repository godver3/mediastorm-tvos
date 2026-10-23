import SwiftUI

/// The Lists tab: the profile's own titles (Continue Watching, Set Aside, Watchlist,
/// Permanent Prequeue), its custom lists, the server's charts, recommendations, then TMDB
/// genres and decades for movies or shows. Each tile opens its whole list as a grid.
struct ListsView: View {
    @EnvironmentObject private var store: CustomListsStore
    @EnvironmentObject private var watchlist: WatchlistStore
    @EnvironmentObject private var titles: TitleStateStore
    @EnvironmentObject private var listShelves: ListShelvesStore
    @State private var kind: BrowseKind = .movies
    @State private var naming = false
    @State private var newName = ""
    @State private var createError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                TileRow(title: String(localized: "For You"), tiles: personalTiles)

                if let customLists = store.lists {
                    TileRow(title: String(localized: "Your Lists"),
                            tiles: customLists.filter { !$0.isSetAside }.map { list in
                                TileSpec(.custom(id: list.id, name: list.name), count: list.itemCount)
                            },
                            onNewList: {
                                newName = ""
                                naming = true
                            })
                    if let createError {
                        Text(createError).font(.callout).foregroundStyle(.red).padding(.horizontal, 80)
                    }
                }

                // Rows from the shelf config wait for it, rather than showing the default
                // services and then swapping them.
                if listShelves.shelves != nil {
                    TileRow(title: String(localized: "Streaming Services"),
                            tiles: services.map { TileSpec(.service($0), logo: $0.logoUrl) })
                }

                let remote = shelves.compactMap { shelf in shelf.remoteQuery.map { _ in shelf } }
                if !remote.isEmpty {
                    TileRow(title: String(localized: "Connected Lists"), tiles: remote.compactMap { shelf in
                        shelf.browseList.map { TileSpec($0) }
                    })
                }

                ForEach(hubs, id: \.title) { hub in
                    TileRow(title: hub.title, tiles: hub.tiles)
                }

                TileRow(title: String(localized: "Charts"), tiles: [
                    .topTen(nil), .topTen(.movies), .topTen(.shows),
                    .trending(.movies), .trending(.shows), .popularOnServer,
                ].map { TileSpec($0) })

                TileRow(title: String(localized: "Recommended"),
                        tiles: [TileSpec(.personalized)] + seeds.map { TileSpec($0) })

                VStack(alignment: .leading, spacing: 56) {
                    KindMenu(kind: $kind)
                        .padding(.horizontal, 80)
                        // Full width, so a move up or down from a tile anywhere in the row lands here.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .focusSection()

                    TileRow(title: String(localized: "Genres"), tiles: kind.genres.map { TileSpec(.genre($0, kind)) })
                    TileRow(title: String(localized: "Decades"), tiles: kind.decades.map { TileSpec(.decade($0, kind)) })
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        // On every visit: lists made or changed elsewhere show up. Everything here is loaded
        // with the tabs, so the rows draw at once and only update in place.
        .onAppear {
            Task { await store.refresh() }
            Task { await titles.refreshHidden() }
            Task { await listShelves.refresh() }
            Task { await titles.refreshContinueWatching() }
        }
        .alert("New List", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await createList() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add titles to it with “Add to List…” on any title.")
        }
    }

    /// Continue Watching (when there is any), Set Aside, Watchlist, Permanent Prequeue, Hidden.
    private var personalTiles: [TileSpec] {
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

    private var shelves: [ShelfConfig] { listShelves.shelves ?? [] }

    private var services: [StreamingService] {
        StreamingService.resolved(shelves.first { $0.id == "streaming-services" }?.streamingServices)
    }

    /// Collection hub shelves: each card opens another shelf's list, with the card's own art.
    private var hubs: [(title: String, tiles: [TileSpec])] {
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
    private var seeds: [BrowseList] {
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

    private func createList() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = store.nameProblem(name) {
            createError = problem
            return
        }
        do {
            try await store.create(name: name)
            createError = nil
        } catch {
            createError = error.localizedDescription
        }
    }
}
