#if os(iOS)
import SwiftUI

/// A titled row of list tiles; empty rows draw nothing.
struct MobileTileRow: View {
    let title: String
    let tiles: [TileSpec]
    /// Ends the row with a New List tile.
    var onNewList: (() -> Void)?

    var body: some View {
        if !tiles.isEmpty || onNewList != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 16).accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(tiles.enumerated()), id: \.element.list) { index, tile in
                            MobileListTile(tile: tile, position: index)
                        }
                        if let onNewList { MobileNewListTile(action: onNewList) }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
            }
        }
    }
}

enum MobileTileMetrics {
    static func size(_ sizeClass: UserInterfaceSizeClass?) -> CGSize {
        sizeClass == .regular ? CGSize(width: 280, height: 158) : CGSize(width: 200, height: 112)
    }
}

/// A list's tile: a 2×2 poster collage for the profile's lists of four or more, otherwise a
/// backdrop from one of the list's first titles (or a service's logo), the name over it.
struct MobileListTile: View {
    let tile: TileSpec
    /// Neighbouring lists often share a top title, so each tile takes a different one.
    let position: Int
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var fetched: TileArt?

    private var size: CGSize { MobileTileMetrics.size(sizeClass) }
    private var preview: TileArt? { tile.art ?? fetched }
    private var title: String { tile.title ?? tile.list.title }

    private var isPersonal: Bool {
        switch tile.list {
        case .custom, .watchlist, .permanentPrequeue, .continueWatching, .hidden: true
        default: false
        }
    }

    var body: some View {
        NavigationLink(value: tile.list) {
            artwork
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .bottomLeading) { if tile.logo == nil { label } }
                .clipShape(RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .task(id: tile.count) {
            guard tile.art == nil, tile.logo == nil else { return }
            fetched = await BrowsePreviews.art(for: tile.list, version: tile.count)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.subheadline.weight(.bold)).lineLimit(2)
            if let count = tile.count {
                Text(count == 1 ? String(localized: "1 title") : String(localized: "\(count) titles"))
                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
            } else if let subtitle = tile.subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private var artwork: some View {
        if let logo = tile.logo {
            Rectangle().fill(.regularMaterial)
                .overlay {
                    RemoteImage(url: Artwork.url(logo, size: "w500"), size: CGSize(width: size.width * 0.6, height: size.height * 0.5),
                                contentMode: .fit) { _ in
                        Text(title).font(.headline)
                    }
                }
        } else if isPersonal, (preview?.posters.count ?? 0) >= 4 {
            collage
        } else {
            RemoteImage(url: Artwork.url(backdrop, size: "w780"), size: size) { _ in placeholder }
        }
    }

    private var backdrop: String? {
        if case let .similar(_, _, _, seedBackdrop?) = tile.list { return seedBackdrop }
        let urls = preview?.backdrops ?? []
        guard !urls.isEmpty else { return nil }
        return isPersonal ? urls[0] : urls[position % urls.count]
    }

    private var collage: some View {
        let cell = CGSize(width: size.width / 2, height: size.height / 2)
        let urls = preview?.posters ?? []
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        RemoteImage(url: index < urls.count ? Artwork.url(urls[index], size: "w342") : nil, size: cell) { _ in
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: cell.width, height: cell.height)
                        .clipped()
                    }
                }
            }
        }
    }

    private var placeholder: some View {
        Rectangle().fill(.quaternary)
            .overlay(alignment: .topTrailing) {
                Image(systemName: isPersonal ? "list.bullet" : "film.stack")
                    .font(.title3).foregroundStyle(.secondary).padding(10)
            }
    }
}

/// Creates a list.
struct MobileNewListTile: View {
    let action: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let size = MobileTileMetrics.size(sizeClass)
        Button(action: action) {
            RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius, style: .continuous)
                .fill(.quaternary)
                .frame(width: size.width, height: size.height)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "plus").font(.title2.weight(.semibold))
                        Text("New List").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.secondary)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New List")
    }
}
#endif
