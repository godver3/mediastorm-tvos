#if os(iOS)
import SwiftUI

/// A list page's toolbar: Sort (tapping the current sort flips its direction), Filter
/// (Movies / Shows, watch status, genres; the profile's own lists), Random and, for the
/// profile's own lists, Rename / Delete.
struct MobileBrowseMenus: View {
    let list: BrowseList
    @Binding var options: BrowseOptions
    let genres: [String]
    let onRandom: (() -> Void)?
    let isPicking: Bool
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        if let onRandom {
            Button(action: onRandom) { Label("Random", systemImage: "dice") }
                .disabled(isPicking)
        }
        if list.filters { filterMenu }
        if !list.sorts.isEmpty || onRename != nil { moreMenu }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $options.kind) {
                Text("Movies and Shows").tag(BrowseKind?.none)
                ForEach(BrowseKind.allCases) { Text($0.noun).tag(Optional($0)) }
            }
            Picker("Status", selection: $options.watch) {
                ForEach(WatchFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            let allGenres = Set(genres).union(options.genres).sorted()
            if !allGenres.isEmpty {
                Menu {
                    ForEach(allGenres, id: \.self) { genre in
                        Toggle(genre, isOn: Binding(get: { options.genres.contains(genre) }, set: { on in
                            if on { options.genres.insert(genre) } else { options.genres.remove(genre) }
                        }))
                    }
                } label: {
                    Label(genreTitle, systemImage: "theatermasks")
                }
            }
            if options.isFiltered {
                Divider()
                Button(role: .destructive) {
                    options.kind = nil
                    options.watch = .all
                    options.genres = []
                } label: {
                    Label("Clear Filters", systemImage: "xmark.circle")
                }
            }
        } label: {
            Label("Filter", systemImage: options.isFiltered
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }

    private var genreTitle: String {
        switch options.genres.count {
        case 0: String(localized: "All Genres")
        case 1: options.genres.first!
        default: String(localized: "\(options.genres.count) Genres")
        }
    }

    private var moreMenu: some View {
        Menu {
            if !list.sorts.isEmpty {
                Section("Sort By") {
                    ForEach(list.sorts, id: \.self) { sort in
                        Button { options.choose(sort) } label: {
                            if sort == options.sort {
                                Label(sort.label, systemImage: sort == .default ? "checkmark"
                                      : options.ascending ? "chevron.up" : "chevron.down")
                            } else {
                                Text(sort.label)
                            }
                        }
                    }
                }
                if list.filters, options.sort == .rating {
                    Picker("Rating Source", selection: $options.ratingSource) {
                        ForEach(RatingSource.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            if let onRename, let onDelete {
                Section {
                    Button(action: onRename) { Label("Rename…", systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) { Label("Delete List…", systemImage: "trash") }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .accessibilityLabel("Sort and Manage")
    }
}

/// Every Continue Watching title as 16:9 cards with progress. Long press offers hiding a
/// title from the row, which takes its card out at once.
struct MobileContinueWatchingGrid: View {
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var cards: [HomeCard]?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if let cards, !cards.isEmpty {
                MobilePosterGrid(items: cards, landscape: true) { card in
                    MobileGridCard(card: card, landscape: true, onHide: { hide(card) })
                }
                .padding(.vertical, 8)
            }
        }
        .overlay {
            if let cards, cards.isEmpty {
                ContentUnavailableView("Nothing to Continue", systemImage: "play.circle",
                                       description: Text("Titles you start watching show up here."))
            } else if cards == nil, let loadError {
                ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if cards == nil {
                ProgressView()
            }
        }
        .navigationTitle("Continue Watching")
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: playback.sessionsEnded) { Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .continueWatchingChanged)) { _ in
            Task { await load() }
        }
    }

    private func load() async {
        do {
            cards = try await APIClient.shared.continueWatching().map(HomeCard.init)
            loadError = nil
        } catch {
            if cards == nil { loadError = error.localizedDescription }
        }
    }

    private func hide(_ card: HomeCard) {
        withAnimation { cards?.removeAll { $0.id == card.id } }
        Task {
            do { try await APIClient.shared.hideFromContinueWatching(seriesID: card.id) } catch { await load() }
        }
    }
}

/// Titles hidden from the profile; long press offers Unhide.
struct MobileHiddenGrid: View {
    @EnvironmentObject private var titles: TitleStateStore

    var body: some View {
        ScrollView {
            if !titles.hidden.isEmpty {
                Text("Touch and hold a title to unhide it.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                MobilePosterGrid(items: titles.hidden) { item in
                    let target = DetailsTarget(item)
                    MobileGridCard(card: HomeCard(id: item.id, target: target, title: target.name,
                                                  subtitle: HomeCard.kindLine(year: item.year, isMovie: item.isMovie),
                                                  overview: nil, artworkURL: target.backdropURL))
                }
            }
        }
        .overlay {
            if titles.hidden.isEmpty {
                if titles.hiddenLoaded {
                    ContentUnavailableView("Nothing Hidden", systemImage: "eye",
                                           description: Text("Nothing is hidden from this profile."))
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle("Hidden")
        .refreshable { await titles.refreshHidden() }
        .task { await titles.refreshHidden() }
    }
}
#endif
