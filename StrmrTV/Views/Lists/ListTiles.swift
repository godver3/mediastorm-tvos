import SwiftUI

// The Lists tab's tiles and rows (`ListsView`).

/// A tile to show: its list, its size when known up front, and artwork when the tab
/// already has it (otherwise the tile fetches the list's first titles).
struct TileSpec {
    let list: BrowseList
    /// Overrides the list's own name (collection hub cards).
    var title: String?
    var count: Int?
    var art: TileArt?
    /// Drawn on a plain panel instead of artwork (streaming services, hub cards without art).
    var logo: String?

    init(_ list: BrowseList, title: String? = nil, count: Int? = nil, art: TileArt? = nil, logo: String? = nil) {
        self.list = list
        self.title = title
        self.count = count
        self.art = art
        self.logo = logo
    }
}

/// Artwork of a list's first titles.
struct TileArt: Hashable {
    var posters: [String] = []
    var backdrops: [String] = []
}

/// A titled row of list tiles.
struct TileRow: View {
    let title: String
    let tiles: [TileSpec]
    /// Ends the row with a "New List" tile.
    var onNewList: (() -> Void)?

    enum TileFocus: Hashable { case tile(BrowseList), newList }
    @FocusState private var focused: TileFocus?
    /// The tile last focused in this row, where focus returns on coming back to it
    /// (as Home does). Without it the focus engine takes the tile nearest the one left.
    @State private var lastFocused: TileFocus?

    private var entry: TileFocus? {
        if let lastFocused, contains(lastFocused) { return lastFocused }
        return tiles.first.map { .tile($0.list) } ?? (onNewList == nil ? nil : .newList)
    }

    private func contains(_ focus: TileFocus) -> Bool {
        switch focus {
        case let .tile(list): tiles.contains { $0.list == list }
        case .newList: onNewList != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 48) {
                    ForEach(Array(tiles.enumerated()), id: \.element.list) { index, tile in
                        ListTile(list: tile.list, title: tile.title ?? tile.list.title, count: tile.count,
                                 given: tile.art, logo: tile.logo, position: index)
                            .focused($focused, equals: .tile(tile.list))
                    }
                    if let onNewList {
                        NewListTile(action: onNewList).focused($focused, equals: .newList)
                    }
                }
            }
            // As on Home: full width with the inset inside, so lazy tiles in the margin stay loaded.
            .contentMargins(.horizontal, 80, for: .scrollContent)
            .scrollClipDisabled()
            .padding(.top, 30)
            .focusSection()
            .defaultFocus($focused, entry, priority: .userInitiated)
            .onChange(of: focused) { _, focus in
                if let focus { lastFocused = focus }
            }
        }
    }
}

/// A list's tile: a 2×2 poster collage for custom lists of four or more, otherwise a
/// backdrop from one of the list's first titles, with the list's name over it.
struct ListTile: View {
    let list: BrowseList
    let title: String
    let count: Int?
    /// Artwork the tab already has; otherwise fetched.
    let given: TileArt?
    let logo: String?
    /// Place in the row. Neighbouring lists often share a top title (the same blockbuster
    /// leads Action, Adventure and 2020s), so each tile takes a different one of its first few.
    let position: Int

    static let size = CGSize(width: 480, height: 270)

    @State private var fetched: TileArt?

    private var preview: TileArt? { given ?? fetched }

    /// The profile's own lists show a poster collage once they have four titles.
    private var isCustom: Bool {
        switch list {
        case .custom, .watchlist, .permanentPrequeue, .continueWatching, .hidden: true
        default: false
        }
    }

    var body: some View {
        NavigationLink(value: list) {
            artwork
                .frame(width: Self.size.width, height: Self.size.height)
                .overlay(alignment: .bottomLeading) { if logo == nil { label } }
        }
        .cardLift()
        .accessibilityLabel(title)
        // Keyed on the count so a list whose contents changed refetches its collage.
        .task(id: count) {
            guard given == nil, logo == nil else { return }
            fetched = await BrowsePreviews.art(for: list, version: count)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 34, weight: .bold)).lineLimit(2)
            if let count {
                Text(count == 1 ? String(localized: "1 title") : String(localized: "\(count) titles"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 40)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private var artwork: some View {
        if let logo {
            Rectangle().fill(.black)
                .overlay {
                    RemoteImage(url: Artwork.url(logo, size: "w500"), size: CGSize(width: 300, height: 130),
                                contentMode: .fit) { _ in
                        Text(title).font(.system(size: 34, weight: .bold))
                    }
                }
        } else if isCustom, (preview?.posters.count ?? 0) >= 4 {
            collage
        } else {
            RemoteImage(url: Artwork.url(backdrop, size: "w780"), size: Self.size) { _ in placeholder }
        }
    }

    private var backdrop: String? {
        if case let .similar(_, _, _, seedBackdrop?) = list { return seedBackdrop }
        let urls = preview?.backdrops ?? []
        guard !urls.isEmpty else { return nil }
        return isCustom ? urls[0] : urls[position % urls.count]
    }

    /// Posters cropped into the four quarters of the tile.
    private var collage: some View {
        let cell = CGSize(width: Self.size.width / 2, height: Self.size.height / 2)
        let urls = preview?.posters ?? []
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        RemoteImage(url: index < urls.count ? Artwork.url(urls[index], size: "w342") : nil, size: cell) { _ in
                            Rectangle().fill(.quaternary)
                        }
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isCustom ? "list.bullet" : "film.stack")
                    .font(.system(size: 50)).foregroundStyle(.secondary).padding(24)
            }
    }
}

/// Creates a custom list.
struct NewListTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Rectangle().fill(.quaternary)
                .frame(width: ListTile.size.width, height: ListTile.size.height)
                .overlay {
                    VStack(spacing: 16) {
                        Image(systemName: "plus").font(.system(size: 60, weight: .semibold))
                        Text("New List").font(.system(size: 34, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                }
        }
        .cardLift()
        .accessibilityLabel("New List")
    }
}

/// The first few titles of each list, for its tile, kept per profile for the app's lifetime so
/// scrolling back and forth or switching Movies / Shows doesn't refetch.
@MainActor
private enum BrowsePreviews {
    private static var cache: [String: TileArt] = [:]

    static func art(for list: BrowseList, version: Int?) async -> TileArt {
        if case .similar = list { return TileArt() }  // the seed's own backdrop
        let key = "\(APIClient.shared.profileID)|\(list)|\(version.map(String.init) ?? "")"
        if let cached = cache[key] { return cached }
        // Four posters: the quick pass, not a whole remote list read and filled in first.
        guard let page = try? await APIClient.shared.browsePage(list, limit: 4, phase: .cards) else { return TileArt() }
        let art = TileArt(posters: page.entries.compactMap(\.posterURL), backdrops: page.entries.compactMap(\.backdropURL))
        cache[key] = art
        return art
    }
}

/// Movies / Shows as a menu button. A segmented picker on tvOS selects whichever
/// segment takes focus, which changes the rows below just by moving past it.
struct KindMenu: View {
    @Binding var kind: BrowseKind

    var body: some View {
        Menu {
            Picker("Browse", selection: $kind) {
                ForEach(BrowseKind.allCases) { Text($0.noun).tag($0) }
            }
        } label: {
            Label(kind.noun, systemImage: "chevron.up.chevron.down")
        }
    }
}
