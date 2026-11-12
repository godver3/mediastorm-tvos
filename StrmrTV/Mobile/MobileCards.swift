#if os(iOS)
import SwiftUI

// The phone's artwork cards: shelf cards at a fixed size, grid cells that fill their column,
// their badges and progress bar. What a tap or long press does is `MobileCardLink`'s.

/// Card sizes on a phone, larger on a regular-width screen (iPad).
enum MobileCardMetrics {
    static func posterWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .regular ? 150 : 116 }
    static func landscapeWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .regular ? 300 : 240 }
    /// The narrowest a grid poster column may be.
    static func gridMinimum(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat { sizeClass == .regular ? 140 : 104 }
    static let cornerRadius: CGFloat = 10
}

/// A Home shelf card: a 2:3 poster, or 16:9 art with the title and line under it. Tap and
/// long press as `MobileCardLink`.
struct MobileCard: View {
    let card: HomeCard
    let landscape: Bool
    /// Overrides the default shelf width.
    var width: CGFloat?
    /// Continue Watching: the row takes the card out itself.
    var onHide: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var size: CGSize {
        let width = width ?? (landscape ? MobileCardMetrics.landscapeWidth(sizeClass) : MobileCardMetrics.posterWidth(sizeClass))
        return CGSize(width: width, height: (landscape ? width * 9 / 16 : width * 3 / 2).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MobileCardLink(card: card, onHide: onHide,
                           preview: AnyView(MobileCardArt(card: card, landscape: landscape, size: size))) {
                MobileCardArt(card: card, landscape: landscape, size: size)
            }
            if landscape {
                Text(card.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(card.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: size.width, alignment: .leading)
    }
}

/// A grid cell: the card's poster (or 16:9 art) filling the column, title and line under it.
struct MobileGridCard: View {
    let card: HomeCard
    var landscape = false
    var showsCaption = true
    var onHide: (() -> Void)?
    var onRemoveFromList: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MobileCardLink(card: card, onHide: onHide, onRemoveFromList: onRemoveFromList) {
                Color.clear
                    .aspectRatio(landscape ? 16 / 9 : 2 / 3, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            MobileCardArt(card: card, landscape: landscape, size: geo.size)
                        }
                    }
            }
            if showsCaption {
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(card.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// A card's face at `size`: artwork (or a symbol or logo tile), badges and progress.
struct MobileCardArt: View {
    let card: HomeCard
    let landscape: Bool
    let size: CGSize

    var body: some View {
        face
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if card.symbol == nil, !card.logoTile {
                    MobileBadges(badge: card.badge, watch: card.watchBadge, unwatchedCount: card.unwatchedCount,
                                 isNew: card.newEpisode != nil)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottom) {
                if ProgressBar.shows(card.progress) {
                    MobileProgressBar(value: card.progress).padding(.horizontal, 8).padding(.bottom, 6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius, style: .continuous))
            .contentShape(.contextMenuPreview,
                          RoundedRectangle(cornerRadius: MobileCardMetrics.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var face: some View {
        if let symbol = card.symbol {
            tile {
                Image(systemName: symbol).font(.system(size: min(size.height * 0.3, 44))).foregroundStyle(.secondary)
            }
        } else if card.logoTile {
            tile {
                RemoteImage(url: Artwork.logoURL(card.logoURL, size: "w500"),
                            size: CGSize(width: size.width * 0.6, height: size.height * 0.45), contentMode: .fit) { _ in
                    Text(card.title).font(.headline)
                }
            }
        } else if !card.collageURLs.isEmpty {
            ArtCollage(urls: card.collageURLs, size: size)
        } else {
            RemoteImage(url: Artwork.url(landscape ? card.artworkURL : (card.posterURL ?? card.artworkURL), size: "w500"),
                        size: size) { _ in
                ZStack {
                    Rectangle().fill(.quaternary)
                    Text(card.title).font(.caption).multilineTextAlignment(.center).padding(6)
                }
            }
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Rectangle().fill(.regularMaterial).overlay { content() }
    }
}

/// A card's badges, compact for a phone: the rank, air date or release status, then the
/// watch state with the unwatched count, as Settings › Card Badges says.
struct MobileBadges: View {
    @ObservedObject private var settings = BadgeSettingsStore.shared
    let badge: CardBadge?
    let watch: CardBadge?
    var unwatchedCount: Int?
    var isNew = false

    var body: some View {
        let badges = settings.visibility.badges(badge: badge, watch: watch, unwatchedCount: unwatchedCount)
        VStack(alignment: .leading, spacing: 4) {
            if isNew { pill(Text("NEW"), symbol: nil).background(Capsule().fill(Color.accentColor)) }
            ForEach(badges, id: \.self) { badge in
                if let count = badge.count {
                    pill(Text(count, format: .number).monospacedDigit(), symbol: badge.symbol)
                        .accessibilityLabel(badge.accessibilityText)
                } else if let symbol = badge.symbol {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black.opacity(0.65)))
                        .accessibilityLabel(badge.text)
                } else {
                    pill(Text(badge.text), symbol: nil)
                }
            }
        }
    }

    private func pill(_ text: Text, symbol: String?) -> some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            text
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(minHeight: 22)
        .background(Capsule().fill(.black.opacity(0.65)))
    }
}

struct MobileProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(Color.white).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

/// Grid columns that fill the width with posters at least `minimum` wide.
struct MobilePosterGrid<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    var landscape = false
    /// Called as one of the last dozen cells comes on screen.
    var onNearEnd: (() -> Void)?
    @ViewBuilder let cell: (Item) -> Cell
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let minimum = MobileCardMetrics.gridMinimum(sizeClass) * (landscape ? 1.55 : 1)
        let nearEnd = Set(items.suffix(12).map(\.id))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 12, alignment: .top)],
                  alignment: .leading, spacing: 18) {
            ForEach(items) { item in
                cell(item).onAppear { if nearEnd.contains(item.id) { onNearEnd?() } }
            }
        }
        .padding(.horizontal, 16)
    }
}
#endif
