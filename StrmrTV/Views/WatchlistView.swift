import SwiftUI

/// The profile's watchlist as a poster grid, most recently added first, with an
/// All / Movies / Shows filter. Long press a poster to remove it. The Watchlist tab
/// shows it bare; opened from the Home row's explore card it carries a heading, since
/// the tab bar then still says Home.
struct WatchlistView: View {
    @EnvironmentObject private var watchlist: WatchlistStore
    @State private var filter: Filter = .all
    @FocusState private var focused: Focus?
    /// A title waiting for its context menu to close before its poster goes (see `remove`).
    @State private var pendingRemoval: DetailsTarget?
    var title: String?

    private enum Focus: Hashable {
        case filter
        case item(String)
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, movies, shows
        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .all: "All"
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

                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .focused($focused, equals: .filter)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .focusSection()

                content
            }
            .padding(.horizontal, CardGridLayout.inset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - CardGridLayout.inset * 2 } action: { gridWidth = $0 }
        }
        .task { await watchlist.refresh() }
        .environment(\.removeFromWatchlist) { remove($0) }
        .onChange(of: focused) { _, focus in
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
