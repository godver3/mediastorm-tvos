import SwiftUI

/// One titled row of cards: 16:9, or posters that may open to 16:9 on focus.
struct ShelfRow: View, Equatable {
    let shelf: HomeShelf
    var focused: FocusState<HomeFocus?>.Binding
    let entry: HomeFocus?
    /// The focused card when focus is in this row, else nil. Rows are compared on it
    /// rather than on the shared focus binding, which SwiftUI can't compare, so a move
    /// along one row re-renders that row and not every row on Home.
    let focusedCard: String?
    /// The card whose context menu is open, while focus is in the menu.
    let menuCard: String?
    /// Where the focused card sits once the row has scrolled to it.
    let position: FocusedCardPosition
    let style: ShelfStyle
    let cardHeight: CGFloat
    /// Where the cards' title and line go.
    let cardText: CardText
    /// Set on Continue Watching: the cards offer hiding the title from the row.
    var onHide: ((HomeCard) -> Void)?

    @State private var scrollPosition = ScrollPosition()
    @State private var geometry: ScrollGeometry?

    private static let spacing: CGFloat = 48
    private static let margin: CGFloat = 80
    /// A focus move along the row: the cards opening and folding, and the scroll to the
    /// focused card. One curve and duration for both, so the cards' widths and the scroll
    /// offset change together; on separate animations the focused card lurched with the
    /// widths, then drifted into place with the scroll.
    private static let focusMove = Animation.easeInOut(duration: 0.25)

    /// The card height at the Large card size: a 480-wide 16:9 card.
    static let baseCardHeight: CGFloat = 270

    /// Room above the cards for the focus lift and shadow, 30 at the Large size.
    static func liftRoom(cardHeight: CGFloat) -> CGFloat { (30 * cardHeight / baseCardHeight).rounded() }
    static func landscapeWidth(cardHeight: CGFloat) -> CGFloat { (cardHeight * 16 / 9).rounded() }
    static func posterWidth(cardHeight: CGFloat) -> CGFloat { (cardHeight * 2 / 3).rounded() }
    private var landscapeWidth: CGFloat { Self.landscapeWidth(cardHeight: cardHeight) }
    /// Every card's width but an expanded one's.
    private var cardWidth: CGFloat { style == .landscape ? landscapeWidth : Self.posterWidth(cardHeight: cardHeight) }

    private var metrics: RowMetrics {
        let order = shelf.focusOrder
        return RowMetrics(count: order.count, cardWidth: cardWidth,
                          focusedWidth: style == .expandingPoster ? landscapeWidth : cardWidth,
                          spacing: Self.spacing,
                          position: position)
    }

    /// The card drawn as focused: the focused one, or the one whose menu is open.
    private var activeCard: String? { focusedCard ?? menuCard }
    private var focusedIndex: Int? { activeCard.flatMap { shelf.focusOrder.firstIndex(of: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shelf.title).font(.headline).padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(spacing: Self.spacing) {
                    if shelf.exploreFirst { exploreCard }
                    ForEach(shelf.shown) { card in
                        let expanded = style == .expandingPoster && activeCard == card.id
                        LandscapeCard(card: card, width: expanded ? landscapeWidth : cardWidth, height: cardHeight,
                                      poster: style != .landscape && !expanded, opens: style == .expandingPoster,
                                      text: cardText,
                                      onHide: onHide.map { hide in { hide(card) } })
                            .animation(Self.focusMove, value: expanded)
                            .focused(focused, equals: HomeFocus(shelf: shelf.id, card: card.id))
                    }
                    if !shelf.exploreFirst { exploreCard }
                }
            }
            // Full screen width with the inset inside: a lazy row unloads cards that
            // leave the scroll view's bounds, so a scroll view inset by the page margin
            // dropped cards that were still visible in that margin.
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
            .scrollClipDisabled()
            .scrollPosition($scrollPosition)
            // The focus engine's own scrolls (focus reaching a card not fully on screen,
            // as in a fast swipe) land on the same offset as the scroll below, so the
            // two never pull the row different ways.
            .scrollTargetBehavior(FocusedCardBehavior(metrics: metrics, focused: focusedIndex))
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in geometry = new }
            // Room above for the focus lift; little below the labels, so the shelf sits
            // low on the screen. Outside the scroll view: inside, the uneven padding made
            // the content taller than the cards, and on device the row then scrolled
            // 11pt vertically ((30 - 8) / 2, centring the card) each time focus settled,
            // and back on the next move.
            .padding(.top, Self.liftRoom(cardHeight: cardHeight))
            .padding(.bottom, 8)
            // The focused card scrolls to the left, middle or right of the screen (the
            // Focused Card Position setting), clamped so the row stays put at its start
            // and stops at its end. The next card is then already on screen (at the
            // right, the previous one), so a single press leaves the focus engine
            // little to scroll; faster presses go through `FocusedCardBehavior`.
            .onChange(of: focusedCard) { _, card in
                guard let card else { return }
                withAnimation(Self.focusMove) { scroll(to: card) }
            }
            // A reload can reorder the row under the same focus (a title just watched
            // moves to the front of Continue Watching). Focus doesn't change, so the
            // scroll above never runs and the row stays where the card used to be.
            .onChange(of: shelf.focusOrder) {
                let current = focused.wrappedValue.flatMap { $0.shelf == shelf.id ? $0 : nil }
                guard let card = (current ?? entry)?.card else { return }
                scroll(to: card)
            }
            .focusSection()
            .defaultFocus(focused, entry, priority: .userInitiated)
        }
        // UI tests find a row by its shelf id, whatever order the profile configured.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shelf-\(shelf.id)")
    }

    /// The binding and the closures are left out: the binding is the same focus state
    /// every render, and the closures only reach the view's state.
    nonisolated static func == (lhs: ShelfRow, rhs: ShelfRow) -> Bool {
        MainActor.assumeIsolated {
            lhs.shelf == rhs.shelf && lhs.entry == rhs.entry && lhs.focusedCard == rhs.focusedCard
                && lhs.menuCard == rhs.menuCard
                && lhs.position == rhs.position && lhs.style == rhs.style && lhs.cardHeight == rhs.cardHeight
                && lhs.cardText == rhs.cardText
                && (lhs.onHide == nil) == (rhs.onHide == nil)
        }
    }

    @ViewBuilder
    private var exploreCard: some View {
        if let explore = shelf.explore {
            // Opens to 16:9 on focus in an expanding poster row, as the title cards do.
            let expanded = style == .expandingPoster && focusedCard == ExploreCard.id
            ExploreCardView(explore: explore, size: CGSize(width: expanded ? landscapeWidth : cardWidth, height: cardHeight),
                            caption: cardText == .below)
                .animation(Self.focusMove, value: expanded)
                .focused(focused, equals: HomeFocus(shelf: shelf.id, card: ExploreCard.id))
        }
    }

    /// Scrolls to an offset, not to a card id: an id with a center anchor asked the
    /// near-start cards for an offset before the row's start. The scroll view clamped it
    /// while focus stayed, but re-applied the stored target when focus left for the tab
    /// bar and clamped it twice the inset over, shifting the row a third of a card.
    /// Cards have known widths, so the offset that places one is known exactly.
    private func scroll(to card: String) {
        guard let index = shelf.focusOrder.firstIndex(of: card), let geometry else { return }
        let x = metrics.offset(focusing: index, container: geometry.containerSize.width)
        #if DEBUG
        Self.log.debug("row \(shelf.id) focus \(index) → x \(Int(x)) (was \(Int(geometry.contentOffset.x + geometry.contentInsets.leading)))")
        #endif
        scrollPosition.scrollTo(x: x)
    }

    #if DEBUG
    private static let log = AppLog(category: "home")
    #endif
}

/// Where the focus engine's scrolls along a row end: the card focus is moving to, at the
/// Focused Card Position. The engine asks before SwiftUI reports the new focus, so the
/// card is read off the engine's own proposal, which brings it just into view
/// (`edgeOverhang` past the edge it moves towards) however many cards a swipe skipped.
/// Scrolls without velocity (`scroll(to:)`, layout) are left alone; the scroll view
/// clamps at the row's ends.
private struct FocusedCardBehavior: ScrollTargetBehavior {
    let metrics: RowMetrics
    /// The card focused while the engine asks: it may be wider than the rest.
    let focused: Int?

    /// How far past the scroll view's edge the engine leaves the card it scrolls to
    /// (measured: the content margin it reveals into).
    static let edgeOverhang: CGFloat = 80

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let dx = context.velocity.dx
        guard dx != 0, metrics.count > 0 else { return }
        let rect = target.rect
        // The card's left edge: at the near edge going left; going right, its right
        // edge is at the far edge (it is not focused yet, so it has the plain width).
        let leading = dx > 0
            ? rect.maxX + Self.edgeOverhang - metrics.cardWidth
            : rect.minX - Self.edgeOverhang
        let index = metrics.index(atLeading: leading, focused: focused)
        target.rect.origin.x = metrics.offset(focusing: index, container: context.containerSize.width)
        #if DEBUG
        Self.log.debug("row scroll \(dx > 0 ? "→" : "←") proposed \(Int(rect.minX)) card \(index) → \(Int(target.rect.minX))")
        #endif
    }

    #if DEBUG
    private static let log = AppLog(category: "home")
    #endif
}
