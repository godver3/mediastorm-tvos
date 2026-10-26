import SwiftUI

/// A 16:9 card with the title underneath, used by the Home rows and the Continue
/// Watching grid; in a poster row, a 2:3 poster (`poster`, with `height` set). Long
/// press offers the title actions (`TitleActionsMenu`); on Continue Watching cards
/// (`onHide` set) the row takes the card out itself.
struct LandscapeCard: View {
    static let width: CGFloat = 480

    let card: HomeCard
    var width: CGFloat = LandscapeCard.width
    /// Nil for 16:9.
    var height: CGFloat?
    /// Draws the title's poster rather than its 16:9 art.
    var poster = false
    /// A poster that opens to 16:9 on focus: both faces are drawn at their own sizes in
    /// the card's animating frame, the poster fading over the 16:9 art, so the card opens
    /// and folds in one motion rather than swapping art (and flashing its placeholder)
    /// when it starts.
    var opens = false
    /// Where the title and line go: under the card, over its art, or nowhere.
    var text = CardText.below
    var onHide: (() -> Void)?

    private var size: CGSize { CGSize(width: width, height: height ?? (width * 9 / 16).rounded()) }

    /// The art a card draws: its poster, else its 16:9 art. Nil for a symbol or logo
    /// tile, which draws none.
    static func artURL(_ card: HomeCard, poster: Bool) -> URL? {
        guard card.symbol == nil, !card.logoTile else { return nil }
        return poster ? Artwork.url(card.posterURL ?? card.artworkURL, size: "w342")
                      : Artwork.url(card.artworkURL, size: "w780")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: size.height)) {
            switch card.link {
            case let .details(target):
                NavigationLink(value: target) { artwork }
                    .cardLift()
                    .contextMenu { TitleActionsMenu(target: target, episode: card.episode, onHideFromContinueWatching: onHide) }
                    .accessibilityLabel("\(card.title), \(card.subtitle)")
            case let .list(list):
                NavigationLink(value: list) { artwork }
                    .cardLift()
                    .accessibilityLabel(card.title)
            case let .action(action):
                HomeActionButton(action: action) { artwork }
                    .cardLift()
                    .accessibilityLabel(card.title)
            case let .channel(channel, program):
                Button { LivePlayback.play(channel, program: program) } label: { artwork }
                    .cardLift()
                    .accessibilityLabel("\(card.title), \(card.subtitle)")
            case let .library(entry):
                LibraryEntryLink(entry: entry) { artwork }
                    .cardLift()
                    .accessibilityLabel("\(card.title), \(card.subtitle)")
            }

            if text == .below { CardCaption(title: card.title, subtitle: card.subtitle, width: width) }
        }
    }

    private var artwork: some View {
        tileOrArt
            .overlay(alignment: .bottom) {
                // A poster opened to 16:9 on focus draws it too, as a 16:9 card (left-aligned,
                // over the same gradient and lifted clear of the progress bar): the Expo app
                // leaves it off, but the user wants it there.
                if text.overlays(poster: poster) {
                    CardTextOverlay(title: card.title, subtitle: card.subtitle, size: size, poster: poster,
                                    hasProgress: ProgressBar.shows(card.progress))
                }
            }
    }

    @ViewBuilder
    private var tileOrArt: some View {
        if let symbol = card.symbol {
            Tile(size: size) {
                Image(systemName: symbol).font(.system(size: 76, weight: .medium)).foregroundStyle(.secondary)
            }
        } else if card.logoTile {
            Tile(size: size) {
                RemoteImage(url: Artwork.logoURL(card.logoURL, size: "w500"), size: CGSize(width: size.width * 0.6, height: size.height * 0.45),
                            contentMode: .fit) { _ in
                    Text(card.title).font(.title3.weight(.bold))
                }
            }
        } else {
            face
            .overlay(alignment: .bottom) {
                if ProgressBar.shows(card.progress) {
                    ProgressBar(fraction: card.progress).padding(poster ? 10 : 16)
                }
            }
            .overlay(alignment: .topLeading) {
                // A poster's "New" sits above its other badge; a 16:9 card's at the top right (as Expo).
                VStack(alignment: .leading, spacing: 8) {
                    if poster, let new = card.newEpisode { NewEpisodeBadgeView(badge: new) }
                    if let badge = card.badge { ArtworkBadge(badge: badge, poster: poster) }
                }
                .padding(poster ? 10 : 14)
            }
            .overlay(alignment: .topTrailing) {
                if !poster, let new = card.newEpisode { NewEpisodeBadgeView(badge: new).padding(14) }
            }
        }
    }

    @ViewBuilder
    private var face: some View {
        if opens {
            ZStack {
                // Kept while the card folds, fading out under the poster fading in.
                if !poster {
                    art(poster: false, size: CGSize(width: ShelfRow.landscapeWidth(cardHeight: size.height), height: size.height))
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
                art(poster: true, size: CGSize(width: ShelfRow.posterWidth(cardHeight: size.height), height: size.height))
                    .opacity(poster ? 1 : 0)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            art(poster: poster, size: size)
        }
    }

    private func art(poster: Bool, size: CGSize) -> some View {
        RemoteImage(url: Self.artURL(card, poster: poster), size: size) { _ in
            Rectangle().fill(.quaternary)
                .overlay(Text(card.title).font(.caption).padding())
        }
    }
}

/// A plain card face for cards without artwork: the system's material, content centred.
private struct Tile<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        Rectangle().fill(.regularMaterial)
            .frame(width: size.width, height: size.height)
            .overlay { content }
    }
}

extension EnvironmentValues {
    /// Runs a Watch Something card's action; set by the Home tab.
    @Entry var homeAction: (HomeAction) -> Void = { _ in }
}

/// A Watch Something card's button. It alone reads `homeAction`: SwiftUI can't compare
/// closures, so every view reading one re-renders whenever the environment is written
/// again, and Home writes it on every focus move. Read in `LandscapeCard`, it re-rendered
/// every card on Home (and its art) on each press, about 50 ms of main-thread work that
/// held back the first frame of the row's scroll.
private struct HomeActionButton<Label: View>: View {
    let action: HomeAction
    @ViewBuilder let label: Label
    @Environment(\.homeAction) private var homeAction

    var body: some View {
        Button { homeAction(action) } label: { label }
    }
}

/// The card on a Home row holding more than its cap. It opens the row's full list.
struct ExploreCardView: View {
    let explore: ExploreCard
    /// The row's card size: 16:9, or a poster's 2:3 in a poster row.
    var size = CGSize(width: LandscapeCard.width, height: 270)
    var caption = true

    var body: some View {
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: size.height)) {
            NavigationLink(value: explore.list) {
                collage
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .bottomLeading) {
                        Text("+\(explore.moreCount)")
                            .font(.system(size: min(44, size.width * 0.18), weight: .bold))
                            .padding(.horizontal, min(22, size.width * 0.08))
                            .padding(.vertical, min(16, size.height * 0.06))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            )
                    }
            }
            .cardLift()
            .accessibilityLabel(String(localized: "See all \(explore.total) in \(explore.title)"))

            if caption {
                CardCaption(title: String(localized: "See All"),
                            subtitle: String(localized: "\(explore.moreCount) more"),
                            width: size.width)
            }
        }
    }

    /// Posters cropped into the four quarters of the card; a 16:9 card (expanded, or in a
    /// landscape row) takes the titles' 16:9 art instead, as the title cards do.
    private var collage: some View {
        let cell = CGSize(width: size.width / 2, height: size.height / 2)
        let landscape = size.width > size.height
        let urls = landscape ? explore.artworkURLs : explore.posterURLs
        return Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<2, id: \.self) { row in
                GridRow {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        RemoteImage(url: index < urls.count ? Artwork.url(urls[index], size: landscape ? "w300" : "w342") : nil,
                                    size: cell) { _ in
                            Rectangle().fill(.quaternary)
                        }
                    }
                }
            }
        }
        .overlay {
            if urls.isEmpty {
                Image(systemName: "square.grid.2x2").font(.system(size: 60)).foregroundStyle(.secondary)
            }
        }
    }
}

struct CardCaption: View {
    let title: String
    let subtitle: String
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.semibold)).lineLimit(1)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}
