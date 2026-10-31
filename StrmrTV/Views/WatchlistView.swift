import SwiftUI

/// The profile's watchlist as a poster grid, most recently added first, with a
/// Movies and Shows / Movies / Shows filter menu. Long press a poster to remove it. The
/// Watchlist tab shows it bare; opened from the Home row's explore card it carries a
/// heading, since the tab bar then still says Home.
struct WatchlistView: View {
    @EnvironmentObject private var watchlist: WatchlistStore
    @State private var filter: Filter = .all
    @FocusState private var focused: Focus?
    /// A title waiting for its context menu to close before its poster goes (see `remove`).
    @State private var pendingRemoval: DetailsTarget?
    /// Where focus was last on the page, where it returns on coming back down from the
    /// tab bar. Without it the focus engine takes what's nearest the tab, the card size menu.
    @State private var lastFocused: Focus?
    var title: String?

    private enum Focus: Hashable {
        case filter, cardSize
        case item(String)
    }

    private var entry: Focus {
        switch lastFocused {
        case let .item(id) where visible.contains(where: { $0.id == id }): .item(id)
        case .cardSize: .cardSize
        default: .filter
        }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, movies, shows
        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .all: "Movies and Shows"
            case .movies: "Movies"
            case .shows: "Shows"
            }
        }

        func includes(_ item: WatchlistItem) -> Bool {
            switch self {
            case .all: true
            case .movies: item.isMovie
            case .shows: !item.isMovie
            }
        }
    }

    private var visible: [WatchlistItem] { watchlist.items.filter(filter.includes) }

    /// Measured grid width; columns are sized to fill it exactly.
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let title { PageHeading(title: title) }

                // A menu, as on the browse lists: focusing it changes nothing, choosing
                // does (a segmented picker switches the filter as focus crosses it).
                HStack(spacing: 24) {
                    Picker(selection: $filter) {
                        ForEach(Filter.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label(filter.label, systemImage: "film")
                    }
                    .pickerStyle(.menu)
                    .focused($focused, equals: .filter)
                    Spacer(minLength: 0)
                    GridCardSizeMenu()
                        .focused($focused, equals: .cardSize)
                }
                .font(.callout)
                .focusSection()

                content
            }
            .padding(.horizontal, CardGridLayout.inset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - CardGridLayout.inset * 2 } action: { gridWidth = $0 }
        }
        .defaultFocus($focused, entry, priority: .userInitiated)
        .task { await watchlist.refresh() }
        .environment(\.removeFromWatchlist) { remove($0) }
        .onChange(of: focused) { _, focus in
            if let focus { lastFocused = focus }
            if let pendingRemoval, focus == .item(pendingRemoval.titleID) { completeRemoval(pendingRemoval) }
        }
    }

    /// As with Continue Watching: the context menu hands focus back to the poster on
    /// closing, so the poster goes once focus is back on it (or after a second).
    private func remove(_ target: DetailsTarget) {
        pendingRemoval = target
        Task {
            try? await Task.sleep(for: .seconds(1))
            if pendingRemoval == target { completeRemoval(target) }
        }
    }

    /// Focus moves to the poster that takes the removed one's place (else the one before,
    /// else the filter), then the title goes; a failure puts it back.
    private func completeRemoval(_ target: DetailsTarget) {
        pendingRemoval = nil
        let shown = visible
        if let index = shown.firstIndex(where: { $0.id == target.titleID }) {
            let rest = shown.filter { $0.id != target.titleID }
            focused = rest.isEmpty ? .filter : .item(rest[min(index, rest.count - 1)].id)
        }
        Task { try? await watchlist.remove(target) }
    }

    @ViewBuilder
    private var content: some View {
        if !watchlist.isLoaded {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
        } else if let error = watchlist.loadError {
            Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 100)
        } else if visible.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "bookmark").font(.system(size: 60)).foregroundStyle(.secondary)
                Text(watchlist.items.isEmpty
                     ? "Your watchlist is empty. Add movies and shows from their details page, or long press a poster."
                     : "Nothing here for this filter.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 100)
        } else {
            CardGrid(items: visible, cardWidth: PosterCard.width, available: gridWidth) { item, width in
                PosterCard(item: item, width: width)
                    .focused($focused, equals: .item(item.id))
            }
        }
    }
}
