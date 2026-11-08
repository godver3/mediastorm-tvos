import SwiftUI

/// The Lists tab: the profile's own titles (Continue Watching, Set Aside, Watchlist,
/// Permanent Prequeue), its custom lists, the server's charts, recommendations, then TMDB
/// genres and decades for movies, shows or both. Each tile opens its whole list as a grid.
struct ListsView: View {
    @EnvironmentObject private var store: CustomListsStore
    @EnvironmentObject private var watchlist: WatchlistStore
    @EnvironmentObject private var titles: TitleStateStore
    @EnvironmentObject private var listShelves: ListShelvesStore
    @ObservedObject private var libraries = LibrariesStore.shared
    @State private var kind: BrowseKind?
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

                // The profile's local, Plex and Jellyfin libraries, each opening its titles.
                if !libraries.libraries.isEmpty {
                    TileRow(title: String(localized: "Libraries"), tiles: libraries.libraries.map { library in
                        TileSpec(.library(library.ref), subtitle: library.tileSubtitle)
                    })
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

                    // All shows each kind's genres, then each kind's decades, as the Expo app does.
                    let kinds = kind.map { [$0] } ?? BrowseKind.allCases
                    ForEach(kinds) { kind in
                        TileRow(title: rowTitle(String(localized: "Genres"), kind),
                                tiles: kind.genres.map { TileSpec(.genre($0, kind)) })
                    }
                    ForEach(kinds) { kind in
                        TileRow(title: rowTitle(String(localized: "Decades"), kind),
                                tiles: kind.decades.map { TileSpec(.decade($0, kind)) })
                    }
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
            Task { await libraries.refresh() }
            Task { await titles.refreshContinueWatching() }
        }
        .alert("New List", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await createList() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add titles to it with “Manage Lists…” on any title.")
        }
    }

    private var catalog: ListsCatalog {
        ListsCatalog(store: store, watchlist: watchlist, titles: titles, listShelves: listShelves)
    }

    /// Continue Watching (when there is any), Set Aside, Watchlist, Permanent Prequeue, Hidden.
    private var personalTiles: [TileSpec] { catalog.personalTiles }

    /// "Genres" under a single kind; "Movie Genres" / "Show Genres" when All shows both.
    private func rowTitle(_ title: String, _ rowKind: BrowseKind) -> String {
        ListsCatalog.rowTitle(title, rowKind, chosen: kind)
    }

    private var shelves: [ShelfConfig] { catalog.shelves }

    private var services: [StreamingService] { catalog.services }

    /// Collection hub shelves: each card opens another shelf's list, with the card's own art.
    private var hubs: [(title: String, tiles: [TileSpec])] { catalog.hubs }

    /// "Because you watched": up to three movies and three shows from Continue Watching.
    private var seeds: [BrowseList] { catalog.seeds }

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
