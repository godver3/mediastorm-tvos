import SwiftUI
import UIKit

struct HomeView: View {
    /// The rows of the Home view shown, built from the profile's shelf config; rebuilt
    /// only when data changes, not on every render (focus moves re-render the page). One
    /// per Home view, kept when switching views (`HomeViewsStore`).
    @ObservedObject var store: HomeStore
    /// A details page or full row is pushed over Home.
    var isCovered = false
    /// The views the View Switcher menu offers (All plus those without a tab); set on the
    /// Home tab while at least one view has no tab of its own. The pill shows only with it
    /// and the Home Layout setting on.
    var viewChoices: [String]?
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @ObservedObject var layout = HomeLayoutStore.shared
    @EnvironmentObject var watchlist: WatchlistStore
    @Environment(\.scenePhase) var scenePhase
    @FocusState var focused: HomeFocus?
    /// The card the hero shows. Follows focus but ignores the momentary nil focus between
    /// two cards, so the hero never flips back to the first item mid-move.
    @State var heroFocus: HomeFocus?
    /// The card focus last had in the rows. On the Top Carousel's buttons the focused
    /// card's info (fading out) keeps showing it, rather than the first row's first card.
    @State var lastRowFocus: HomeFocus?
    /// The card each row last had focus on, so moving between rows returns to it.
    @State var rowFocus: [String: String] = [:]
    @FocusState var guideFocused: Bool
    /// Set while a page is pushed over Home, so the card left is refocused on the way back.
    @State private var refocusOnAppear = false
    /// A card waiting for its context menu to close before it leaves its row (see `remove`).
    @State var pendingRemoval: PendingRemoval?
    /// The promoted Top 10's current title.
    @State var promotedIndex = 0
    // Internal rather than private from here on: the Classic and Carousel pages are
    // extensions in their own files.
    @ObservedObject var style = HomeStyleStore.shared
    /// The carousel's current slide.
    @State var carouselIndex = 0
    /// When the carousel last moved on by itself.
    @State var carouselAdvancedAt = Date.distantPast
    /// The Top Carousel is up, rather than crossfaded away for focus in the rows.
    @State var carouselShown = true
    /// The page's bottom safe-area inset, which the carousel's buttons sit on.
    @State var safeBottom: CGFloat = 60
    /// The art prefetch waiting for focus to settle. A box, so restarting it on every
    /// focus move doesn't re-render the page.
    @State private var artPrefetch = PendingTask()
    /// The row the full hero's rows show, which sizes them: the focused row, once the fade
    /// from the last one has hidden the swap.
    @State var shownRow: String?
    /// The full hero's page while it fades from row to row.
    @State var rowFade = 1.0
    @State var rowSwap = PendingTask()
    /// The card left in the row fading out, whose info shows until the swap.
    @State var swapFrom: HomeFocus?
    /// How long focus rests on a card before Home loads the art around it.
    static let artSettle: Duration = .milliseconds(150)

    /// A row's height: the row title, room for the focus lift, the card and its caption
    /// (60 pt of text under the gap that clears the lift). Without captions the gap stays,
    /// plus 24 pt so the next row's title sits nearer its own cards than a focused card
    /// above it.
    static func rowHeight(cardHeight: CGFloat, captions: Bool) -> CGFloat {
        let caption = PosterFocusStyle.captionSpacing(cardHeight: cardHeight) + (captions ? 60 : 24)
        return 46 + ShelfRow.liftRoom(cardHeight: cardHeight) + cardHeight + caption + 20
    }
    /// Room left above the hero for the tab bar when the hero is smaller than full.
    static let tabBarClearance: CGFloat = 90

    /// The Card Size height; the promoted Top 10 row, which has its own layout, keeps it.
    var cardHeight: CGFloat { (ShelfRow.baseCardHeight * layout.effectiveCardScale).rounded() }

    /// A row's card height: its style's own size (Poster, Expanding Poster or Landscape
    /// Cards), else Card Size.
    func cardHeight(forShelf id: String) -> CGFloat {
        guard id != HomeShelf.promotedTopTenID else { return cardHeight }
        return (ShelfRow.baseCardHeight * layout.cardScale(for: layout.style(for: id))).rounded()
    }

    func rowHeight(forShelf id: String) -> CGFloat {
        Self.rowHeight(cardHeight: cardHeight(forShelf: id), captions: layout.effectiveCardText == .below)
    }

    /// The tallest row on the page.
    var tallestRowHeight: CGFloat {
        store.slots.map { rowHeight(forShelf: $0.id) }.max()
            ?? Self.rowHeight(cardHeight: cardHeight, captions: layout.effectiveCardText == .below)
    }

    /// The rows' viewport with the full hero: the shown row's height, so that row sits on
    /// the bottom edge and the one under it never shows; a row of smaller cards brings the
    /// hero down with it. On the carousel's controls (or before any row has focus), the
    /// tallest row's, which the carousel's controls are laid out for.
    var rowHeight: CGFloat {
        guard let shelf = shownRow ?? heroFocus?.shelf, store.slots.contains(where: { $0.id == shelf }) else {
            return tallestRowHeight
        }
        return rowHeight(forShelf: shelf)
    }
    var heroSize: HeroSize { layout.effectiveHeroSize }
    /// How often an idle Home asks the server whether anything changed.
    static let staleCheckInterval: Duration = .seconds(300)

    var shelves: [HomeShelf] { store.shelves }

    /// Where focus lands on moving into a row: the card it last left there, else the
    /// first. Without this the focus engine takes the card under the one left, which in a
    /// row still at its start is a card or two in.
    func entry(_ shelf: HomeShelf) -> HomeFocus? {
        if shelf.id == HomeShelf.promotedTopTenID { return HomeFocus(shelf: shelf.id, card: PromotedTopTenRow.focusID) }
        let remembered = rowFocus[shelf.id].map { HomeFocus(shelf: shelf.id, card: $0) }
        if let remembered, hero(remembered) != nil { return remembered }
        return shelf.focusOrder.first.map { HomeFocus(shelf: shelf.id, card: $0) }
    }
    /// What the hero shows for a focus: a shown card, or a row's explore card.
    func hero(_ focus: HomeFocus?) -> HeroContent? {
        guard let focus, let shelf = shelves.first(where: { $0.id == focus.shelf }) else { return nil }
        if focus.card == ExploreCard.id, let explore = shelf.explore {
            return HeroContent(explore: explore)
        }
        if shelf.id == HomeShelf.promotedTopTenID {
            let cards = Array(shelf.shown)
            return cards.isEmpty ? nil : HeroContent(cards[min(promotedIndex, cards.count - 1)])
        }
        return shelf.shown.first { $0.id == focus.card }.map(HeroContent.init)
    }

    /// Where focus goes on entering the rows: the card last left, else the first row's
    /// entry (a placeholder while that row loads; see `firstRowEntry`).
    var rememberedFocus: HomeFocus? {
        if hero(heroFocus) != nil { return heroFocus }
        if hero(lastRowFocus) != nil { return lastRowFocus }
        return firstRowEntry
    }

    /// With nothing focused yet the hero shows the first loaded row's card while the row
    /// above it loads; with a placeholder focused it shows nothing.
    var hero: HeroContent? {
        hero(rememberedFocus) ?? (focused == nil ? hero(shelves.first.flatMap(entry)) : nil)
    }

    var body: some View {
        Group {
            if style.isClassic { classicPage } else { stackedPage }
        }
        // Floats over the hero, so turning it on moves nothing.
        .overlay(alignment: .top) {
            if let viewChoices, layout.viewSwitcher {
                HomeViewSwitcher(view: store.view, choices: viewChoices)
                    .padding(.top, HomeViewSwitcher.top)
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
        .task {
            store.watchlist = watchlist.items
            // Back on a view already loaded: its layout to Settings, and a reload if stale.
            if store.hasLoaded {
                store.activate()
                await store.refreshIfStale()
            } else {
                await store.load()
            }
        }
        // While Home is up, check now and then whether the server's Home changed.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.staleCheckInterval)
                if !isCovered { await store.refreshIfStale() }
            }
        }
        .onAppear {
            // Back from details or the player: focus the card that was left. Not on a
            // tab switch: focus is still on the tab bar then, and taking it put a card
            // under the next Select, which opened its details.
            guard refocusOnAppear else { return }
            refocusOnAppear = false
            guard let heroFocus else { return }
            if heroFocus.shelf == HomeCarousel.focusShelf || hero(heroFocus) != nil {
                focused = heroFocus
            } else if let first = shelves.first(where: { $0.id == heroFocus.shelf })?.focusOrder.first {
                // The card is gone (hidden from its details page): its row's first one.
                focused = HomeFocus(shelf: heroFocus.shelf, card: first)
            }
        }
        .onChange(of: isCovered) { _, covered in
            if covered { refocusOnAppear = true } else { Task { await store.refreshIfStale() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfStale() } }
        }
        .onChange(of: watchlist.items) { _, items in store.watchlist = items }
        .onChange(of: store.shelves) { old, new in refocusIfGone(from: old, to: new) }
        .onChange(of: store.slots) { _, slots in refocusFromPlaceholder(slots) }
        .environment(\.removeFromWatchlist) { removeFromWatchlist($0) }
        .onChange(of: playback.sessionsEnded) { Task { await store.reloadPlaybackRows() } }
        .onReceive(NotificationCenter.default.publisher(for: .continueWatchingChanged)) { _ in
            Task { await store.reloadPlaybackRows() }
        }
        // Hidden / unhidden titles leave or rejoin every row the server builds.
        .onReceive(NotificationCenter.default.publisher(for: .titleStateChanged)) { _ in
            Task { await store.load() }
        }
        .onChange(of: focused) { _, focus in
            if let pendingRemoval, focus == pendingRemoval.focus {
                completeRemoval(pendingRemoval)
                return
            }
            if let focus {
                heroFocus = focus
                if focus.shelf != HomeCarousel.focusShelf { lastRowFocus = focus }
                rowFocus[focus.shelf] = focus.card
                artPrefetch.restart {
                    try? await Task.sleep(for: Self.artSettle)
                    guard !Task.isCancelled else { return }
                    prefetchArt(around: focus)
                }
            }
        }
        .onChange(of: guideFocused) { _, isFocused in
            if isFocused { focused = style.isClassic ? rememberedFocus : carouselEntry }
        }
    }

    /// Loads the art of the cards focus can reach next, so it is in memory when they
    /// come on screen and the hero changes to them: two cards either side in the row,
    /// and the card focus lands on in the rows above and below. Each gets both card
    /// shapes (a poster row opens to 16:9 on focus) and its hero backdrop.
    private func prefetchArt(around focus: HomeFocus) {
        guard let row = shelves.firstIndex(where: { $0.id == focus.shelf }) else { return }
        var targets: [HomeFocus] = []
        let order = shelves[row].focusOrder
        if let index = order.firstIndex(of: focus.card) {
            for offset in [1, -1, 2, -2] where order.indices.contains(index + offset) {
                targets.append(HomeFocus(shelf: focus.shelf, card: order[index + offset]))
            }
        }
        for neighbour in [row + 1, row - 1] where shelves.indices.contains(neighbour) {
            if let entry = entry(shelves[neighbour]) { targets.append(entry) }
        }

        for target in targets {
            let height = cardHeight(forShelf: target.shelf)
            let poster = CGSize(width: ShelfRow.posterWidth(cardHeight: height), height: height)
            let landscape = CGSize(width: ShelfRow.landscapeWidth(cardHeight: height), height: height)
            if let card = shelves.first(where: { $0.id == target.shelf })?.shown.first(where: { $0.id == target.card }) {
                ImagePipeline.prefetch(LandscapeCard.artURL(card, poster: true), size: poster)
                ImagePipeline.prefetch(LandscapeCard.artURL(card, poster: false), size: landscape)
            }
            ImagePipeline.prefetch(Artwork.url(hero(target)?.backdropURL), size: UIScreen.main.bounds.size)
        }
    }

    /// The card whose context menu is open: the last card focused, while focus is in a
    /// context menu. The menu takes focus off Home, and an expanded poster would otherwise
    /// fold back to a poster behind it. Worked out in the same render that focus goes, as
    /// UIKit has moved focus to the menu by then; set from `onChange(of: focused)` it came a
    /// render late, so the card folded and opened again, and on Back focus came back to a
    /// different card.
    var menuFocus: HomeFocus? {
        focused == nil && Self.contextMenuHasFocus() ? heroFocus : nil
    }

    /// Whether focus has gone to a context menu (rather than, say, the tab bar). The
    /// card button's pressed state can't tell: after a long press opens the menu it never
    /// goes back to unpressed, so the next long press doesn't register.
    private static func contextMenuHasFocus() -> Bool {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                var view = UIFocusSystem.focusSystem(for: window)?.focusedItem as? UIView
                while let current = view {
                    if String(describing: type(of: current)).contains("ContextMenu") { return true }
                    view = current.superview
                }
            }
        }
        return false
    }
}
