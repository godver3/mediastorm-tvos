#if os(iOS)
import SwiftUI

/// The Lists tab on a phone: For You (Continue Watching, Set Aside, Watchlist, Permanent
/// Prequeue, Hidden), the profile's lists, libraries, streaming services, connected lists,
/// collection hubs, charts, recommendations, then TMDB genres and decades for movies, shows
/// or both. Each tile opens its list (`MobileListPage`). The toolbar makes a list, asks the
/// AI and picks Movies / Shows for the genre and decade rows.
struct MobileListsView: View {
    @EnvironmentObject private var store: CustomListsStore
    @EnvironmentObject private var watchlist: WatchlistStore
    @EnvironmentObject private var titles: TitleStateStore
    @EnvironmentObject private var listShelves: ListShelvesStore
    @ObservedObject private var libraries = LibrariesStore.shared
    @AppStorage("mobile.lists.kind") private var kindRaw = ""
    @State private var naming = false
    @State private var newName = ""
    @State private var createError: String?
    @State private var askingAI = false
    @State private var aiPrompt = ""
    @State private var aiList: BrowseList?

    private var kind: BrowseKind? { BrowseKind(rawValue: kindRaw) }

    private var catalog: ListsCatalog {
        ListsCatalog(store: store, watchlist: watchlist, titles: titles, listShelves: listShelves)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                MobileTileRow(title: String(localized: "For You"), tiles: catalog.personalTiles)
                if let custom = catalog.customTiles {
                    MobileTileRow(title: String(localized: "Your Lists"), tiles: custom, onNewList: startNewList)
                    if let createError {
                        Text(createError).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16)
                    }
                }
                if !libraries.libraries.isEmpty {
                    MobileTileRow(title: String(localized: "Libraries"), tiles: libraries.libraries.map {
                        TileSpec(.library($0.ref), subtitle: $0.tileSubtitle)
                    })
                }
                // Rows from the shelf config wait for it, rather than showing the default
                // services and then swapping them.
                if listShelves.shelves != nil {
                    MobileTileRow(title: String(localized: "Streaming Services"),
                                  tiles: catalog.services.map { TileSpec(.service($0), logo: $0.logoUrl) })
                }
                MobileTileRow(title: String(localized: "Connected Lists"), tiles: catalog.connectedTiles)
                ForEach(catalog.hubs, id: \.title) { hub in
                    MobileTileRow(title: hub.title, tiles: hub.tiles)
                }
                MobileTileRow(title: String(localized: "Charts"), tiles: ListsCatalog.charts.map { TileSpec($0) })
                MobileTileRow(title: String(localized: "Recommended"),
                              tiles: [TileSpec(.personalized)] + catalog.seeds.map { TileSpec($0) })
                // All shows each kind's genres, then each kind's decades, as the Expo app does.
                ForEach(discoveryRows, id: \.id) { row in
                    MobileTileRow(title: row.title, tiles: row.tiles)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("Lists")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    aiPrompt = ""
                    askingAI = true
                } label: {
                    Label("Ask AI", systemImage: "sparkles")
                }
                Menu {
                    Picker("Genres and Decades", selection: $kindRaw) {
                        Text("Movies and Shows").tag("")
                        ForEach(BrowseKind.allCases) { Text($0.noun).tag($0.rawValue) }
                    }
                    Divider()
                    Button(action: startNewList) { Label("New List…", systemImage: "plus") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .refreshable { await refresh() }
        // On every visit: lists made or changed elsewhere show up.
        .onAppear { Task { await refresh() } }
        .navigationDestination(item: $aiList) { MobileListPage(list: $0) }
        .alert("New List", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") { Task { await createList() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add titles to it with “Manage Lists…” on any title.")
        }
        .alert("Ask AI", isPresented: $askingAI) {
            TextField("A cozy mystery from the 90s", text: $aiPrompt)
            Button("Ask") {
                let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prompt.isEmpty { aiList = .askAI(prompt) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Describe what you're in the mood for.")
        }
    }

    /// Genre rows then decade rows, for the chosen kind or both. One list with its own ids:
    /// two `ForEach` over the kinds would give the stack duplicate ids and drop rows.
    private var discoveryRows: [(id: String, title: String, tiles: [TileSpec])] {
        let kinds = kind.map { [$0] } ?? BrowseKind.allCases
        let genres = kinds.map { rowKind in
            ("genres-\(rowKind.rawValue)", ListsCatalog.rowTitle(String(localized: "Genres"), rowKind, chosen: kind),
             rowKind.genres.map { TileSpec(.genre($0, rowKind)) })
        }
        let decades = kinds.map { rowKind in
            ("decades-\(rowKind.rawValue)", ListsCatalog.rowTitle(String(localized: "Decades"), rowKind, chosen: kind),
             rowKind.decades.map { TileSpec(.decade($0, rowKind)) })
        }
        return genres + decades
    }

    private func startNewList() {
        newName = ""
        naming = true
    }

    private func refresh() async {
        async let a: Void = store.refresh()
        async let b: Void = titles.refreshHidden()
        async let c: Void = listShelves.refresh()
        async let d: Void = libraries.refresh()
        async let e: Void = titles.refreshContinueWatching()
        _ = await (a, b, c, d, e)
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
#endif
