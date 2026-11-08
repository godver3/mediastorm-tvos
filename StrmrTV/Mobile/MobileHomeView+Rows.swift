#if os(iOS)
import SwiftUI

// Home's rows, explore card and loading placeholder (the carousel is `MobileHomeCarousel`).

/// One titled row. A row longer than its cap ends (or starts) with the explore card, and
/// its title opens the whole list too.
struct MobileShelfRow: View {
    let shelf: HomeShelf
    var landscape = false
    var onHide: ((HomeCard) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header.padding(.horizontal, 16)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    if shelf.exploreFirst { explore }
                    ForEach(shelf.shown) { card in
                        MobileCard(card: card, landscape: landscape, onHide: onHide.map { hide in { hide(card) } })
                    }
                    if !shelf.exploreFirst { explore }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelf-\(shelf.id)")
    }

    @ViewBuilder
    private var header: some View {
        if let explore = shelf.explore {
            NavigationLink(value: explore.list) {
                HStack(spacing: 4) {
                    Text(shelf.title).font(.title3.weight(.semibold))
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        } else {
            Text(shelf.title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var explore: some View {
        if let explore = shelf.explore { MobileExploreCard(explore: explore, landscape: landscape) }
    }
}

/// The card closing a row that holds more than its cap: four of the titles it doesn't show
/// and how many more there are. It opens the whole list.
struct MobileExploreCard: View {
    let explore: ExploreCard
    let landscape: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var size: CGSize {
        let width = landscape ? MobileCardMetrics.landscapeWidth(sizeClass) : MobileCardMetrics.posterWidth(sizeClass)
        return CGSize(width: width, height: (landscape ? width * 9 / 16 : width * 3 / 2).rounded())
    }

    var body: some View {
        NavigationLink(value: explore.list) {
            VStack(alignment: .leading, spacing: 6) {
                collage
                    .frame(width: size.width, height: size.height)
                    .overlay { Color.black.opacity(0.45) }
                    .overlay {
                        VStack(spacing: 2) {
                            Text("+\(explore.moreCount)").font(.title2.bold())
                            Text("See All").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius, style: .continuous))
                if landscape {
                    Text("See All").font(.footnote.weight(.semibold))
                    Text("\(explore.total) titles").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: size.width, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See all \(explore.total) in \(explore.title)")
    }

    private var collage: some View {
        let urls = landscape ? explore.artworkURLs : explore.posterURLs
        let cell = CGSize(width: size.width / 2, height: size.height / 2)
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
}

struct MobileShelfPlaceholder: View {
    let title: String
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let width = MobileCardMetrics.posterWidth(sizeClass)
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 16)
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius).fill(.quaternary)
                        .frame(width: width, height: width * 1.5)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .redacted(reason: .placeholder)
    }
}
#endif
