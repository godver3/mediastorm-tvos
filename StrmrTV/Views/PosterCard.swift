import SwiftUI

/// Portrait poster that opens details, used by the Search, Watchlist and list grids.
/// Long press offers the title actions (`TitleActionsMenu`).
struct PosterCard: View {
    static let width: CGFloat = 240
    static let height: CGFloat = 360

    let target: DetailsTarget
    let badge: CardBadge?
    /// Watched or in progress, shown under `badge`.
    var watchBadge: CardBadge?
    let subtitle: String
    /// Grids that fill their width pass the column width; height keeps the 2:3 shape.
    var width: CGFloat = PosterCard.width
    /// Set in a custom list's grid: offers removing the title from that list.
    var onRemoveFromList: (() -> Void)?
    /// Off on a kids profile's details rows, where (as in the Expo app) titles don't open.
    var opens = true

    /// Drives the lift. The style's `\.isFocused` environment goes stale when focus comes back
    /// from a modal (e.g. the Add to List sheet), leaving a focused card un-lifted.
    @FocusState private var isFocused: Bool

    private var height: CGFloat { width * Self.height / Self.width }

    /// `rank` (Top 10) shows as the first badge, as on Home's Top 10 row.
    init(title: Title, width: CGFloat = PosterCard.width, opens: Bool = true, rank: Int? = nil) {
        self.width = width
        self.opens = opens
        target = DetailsTarget(title)
        badge = rank.map { CardBadge(text: "#\($0)") } ?? ReleaseBadge.forTitle(title)
        watchBadge = CardBadge.forWatchState(title.watchState)
        subtitle = Self.subtitle(year: title.year, isMovie: title.isMovie)
    }

    /// A hidden title (the Hidden grid).
    init(hidden item: HiddenItem, width: CGFloat = PosterCard.width) {
        self.width = width
        target = DetailsTarget(item)
        badge = nil
        subtitle = Self.subtitle(year: item.year, isMovie: item.isMovie)
    }

    init(item: WatchlistItem, width: CGFloat = PosterCard.width, onRemoveFromList: (() -> Void)? = nil) {
        self.width = width
        self.onRemoveFromList = onRemoveFromList
        target = DetailsTarget(item)
        badge = ReleaseBadge.forTitle(item)
        watchBadge = CardBadge.forWatchState(item.watchState)
        subtitle = Self.subtitle(year: item.year, isMovie: item.isMovie)
    }

    private static func subtitle(year: Int?, isMovie: Bool) -> String {
        [year.map(String.init), isMovie ? String(localized: "Movie") : String(localized: "Series")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: height)) {
            Group {
                if opens {
                    NavigationLink(value: target) { artwork }
                } else {
                    Button {} label: { artwork }
                }
            }
            .buttonStyle(PosterFocusStyle(isFocused: isFocused))
            .focused($isFocused)
            .contextMenu { TitleActionsMenu(target: target, onRemoveFromList: onRemoveFromList) }
            .accessibilityLabel(target.name)

            VStack(alignment: .leading, spacing: 4) {
                Text(target.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var artwork: some View {
        RemoteImage(url: Artwork.url(target.displayPosterURL, size: "w500"), size: CGSize(width: width, height: height)) { _ in
            Rectangle().fill(.quaternary)
                .overlay(Text(target.name).font(.caption).multilineTextAlignment(.center).padding())
        }
        .overlay(alignment: .topLeading) {
            ArtworkBadges(badges: [badge, watchBadge].compactMap { $0 }).padding(10)
        }
    }
}

/// A gentler lift than `.card`, used by every artwork card (posters and 16:9 tiles): a small
/// scale, a soft shadow and a thin white focus ring, without the system card's white focus
/// highlight. The ring is for dark cards over a black page (Ask AI on Home), where the lift
/// and its black shadow alone don't show focus; the Android TV app draws the same (1 dp).
struct PosterFocusStyle: ButtonStyle {
    let isFocused: Bool

    /// How much a focused card grows.
    static let focusedScale: CGFloat = 1.06
    static let ringColor = Color.white.opacity(0.7)
    static let ringWidth: CGFloat = 2
    static let cornerRadius: CGFloat = 12

    /// The gap from a card to the caption under it: how far the lift pushes the card's
    /// bottom edge down, plus 12 pt that stay clear while it is focused.
    static func captionSpacing(cardHeight: CGFloat) -> CGFloat {
        (cardHeight * (focusedScale - 1) / 2).rounded(.up) + 12
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Self.ringColor, lineWidth: Self.ringWidth)
                    .opacity(isFocused ? 1 : 0)
            }
            // Scoped to the lift alone: over the whole label it also took the card's width
            // change, so an expanding poster folded on this quicker curve, not the row's.
            .animation(.easeOut(duration: 0.15)) { lifted in
                lifted
                    .scaleEffect(configuration.isPressed ? 1.02 : isFocused ? Self.focusedScale : 1)
                    .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 16, y: 10)
            }
    }
}

/// Applies `PosterFocusStyle` with its own focus tracking, for cards that have no focus binding.
private struct CardLift: ViewModifier {
    /// The style's `\.isFocused` environment goes stale when focus comes back from a modal.
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .buttonStyle(PosterFocusStyle(isFocused: isFocused))
            .focused($isFocused)
    }
}

extension View {
    /// The shared artwork-card lift; use in place of `.buttonStyle(.card)`.
    func cardLift() -> some View { modifier(CardLift()) }
}

/// "Add to Watchlist" / "Remove from Watchlist" for a context menu. Where the card leaves
/// the screen with the title (the Watchlist grid, Home's Watchlist row), that view removes
/// it through `removeFromWatchlist`, so it can move focus off the card first.
struct WatchlistMenuButton: View {
    @EnvironmentObject private var watchlist: WatchlistStore
    @Environment(\.removeFromWatchlist) private var removeHere
    let target: DetailsTarget

    var body: some View {
        if watchlist.contains(target, server: nil) {
            Button(role: .destructive) { toggle(add: false) } label: {
                Label("Remove from Watchlist", systemImage: "minus.circle")
            }
        } else {
            Button { toggle(add: true) } label: {
                Label("Add to Watchlist", systemImage: "plus")
            }
        }
    }

    private func toggle(add: Bool) {
        if !add, let removeHere { return removeHere(target) }
        Task { try? await add ? watchlist.add(target) : watchlist.remove(target) }
    }
}

extension EnvironmentValues {
    /// Set by a view whose card goes with the title when it leaves the watchlist. The
    /// context menu is still up when its button runs and hands focus back to the card on
    /// closing, so a card removed at once left focus nowhere until the next press.
    @Entry var removeFromWatchlist: ((DetailsTarget) -> Void)?
}
