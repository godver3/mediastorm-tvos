import SwiftUI

/// Collection hub cards. A link without its own art or logo shows a preview of the list it
/// opens, as the Expo home does: a 2×2 of its first titles' art, or one backdrop when fewer
/// than four have art. Only a list that gives no art at all falls back to the name tile.
enum HubCards {
    static func cards(_ links: [HomeSource.HubLink], cap: Int) async -> [HomeCard] {
        // One task per shown link (not a task group: see the Swift 6.4 group miscompile),
        // all in flight at once; the previews share the Lists tab's per-profile cache.
        let tasks = links.prefix(cap).map { link in
            Task { @MainActor () -> TileArt? in
                guard link.art == nil, link.logo == nil else { return nil }
                return await BrowsePreviews.art(for: link.list, version: nil)
            }
        }
        var previews: [TileArt?] = []
        for task in tasks { previews.append(await task.value) }
        return links.enumerated().map { index, link in
            card(link, preview: index < previews.count ? previews[index] : nil)
        }
    }

    static func card(_ link: HomeSource.HubLink, preview: TileArt?) -> HomeCard {
        let backdrops = preview?.backdrops ?? []
        let posters = preview?.posters ?? []
        let collage = backdrops.count >= 4 ? Array(backdrops.prefix(4))
            : posters.count >= 4 ? Array(posters.prefix(4)) : []
        let backdrop = link.art ?? backdrops.first
        var card = HomeCard(id: "hub-\(link.id)", link: .list(link.list), title: link.name,
                            subtitle: link.list.title, backdropURL: backdrop,
                            logoURL: link.logo, logoTile: backdrop == nil && collage.isEmpty)
        card.collageURLs = collage
        return card
    }
}

/// Four images in the quarters of `size` (a hub card's preview).
struct ArtCollage: View {
    let urls: [String]
    let size: CGSize

    var body: some View {
        let cell = CGSize(width: size.width / 2, height: size.height / 2)
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        RemoteImage(url: index < urls.count ? Artwork.url(urls[index], size: "w300") : nil, size: cell) { _ in
                            Rectangle().fill(.quaternary)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
