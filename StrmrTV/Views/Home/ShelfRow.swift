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
    /// Whether an expanding poster opens and folds in motion; off, it snaps.
    let animateExpansion: Bool
    /// Set on Continue Watching: the cards offer hiding the title from the row.
    var onHide: ((HomeCard) -> Void)?

    @State private var scrollPosition = ScrollPosition()
    @State private var containerWidth: CGFloat?

    private static let spacing: CGFloat = 48
    private static let margin: CGFloat = 80
    /// A focus move along the row: the cards opening and folding, and the scroll to the
    /// focused card. One curve and duration for both, so the cards' widths and the scroll
    /// offset change together; on separate animations the focused card lurched with the
    /// widths, then drifted into place with the scroll.
    private static let focusMove = Animation.easeInOut(duration: 0.25)

    /// The focus move's animation in this row: none in an expanding poster row with
    /// Animate Expansion off, where the cards snap and the scroll with them, so the
    /// focused card doesn't jump open, then drift into place.
    private var moveAnimation: Animation? {
        style == .expandingPoster && !animateExpansion ? nil : Self.focusMove
    }

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
                            .animation(moveAnimation, value: expanded)
                            .focused(focused, equals: HomeFocus(shelf: shelf.id, card: card.id))
                    }
                    if !shelf.exploreFirst { exploreCard }
                }
            }
            // Full screen width with the inset inside: a lazy row unloads cards that
            // leave the scroll view's bounds, so a scroll view inset by the page margin
            // dropped cards that were still visible in that margin.
            .contentMargins(.horizontal, Self.margin, for: .scrollContent)
            // As tall as the cards: a horizontal scroll view takes all the height offered,
            // and in Home's fixed-height rows it centred the cards in the spare room, so
            // without captions they sat well below the row's title.
            .fixedSize(horizontal: false, vertical: true)
            .scrollClipDisabled()
            .scrollPosition($scrollPosition)
            // The scroll below is the row's only one, as on Home's column of rows. The
            // focus engine scrolls when focus reaches a card not fully on screen, and
            // asks before SwiftUI reports the new focus, so it started its own animation
            // just before the scroll below set off for the same card on another curve;
            // the second replaced the first mid-flight, and the row jumped 50-70pt in
            // the first frame, then stepped unevenly. Focus still moves to that card.
            .scrollDisabled(true)
            // The width alone: the whole geometry changes every frame of a scroll, and
            // re-rendered the row each frame.
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.containerSize.width }) { _, new in containerWidth = new }
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
            // right, the previous one). The scroll is animated on the same curve as the
            // cards opening and folding, so it and their widths move together.
            // It starts once the render that moved focus is on screen: a scroll's clock
            // runs from when it is asked for, the cards' widths from when that render is
            // committed, which can take a few frames. Asked for in the same update, the
            // scroll was half done before the cards began to open, and the card it aimed
            // at, already open in its sums, overshot and drifted back as they caught up.
            .onChange(of: focusedCard) { _, card in
                guard let card else { return }
                DispatchQueue.main.async { withAnimation(moveAnimation) { scroll(to: card) } }
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
                && lhs.cardText == rhs.cardText && lhs.animateExpansion == rhs.animateExpansion
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
                .animation(moveAnimation, value: expanded)
                .focused(focused, equals: HomeFocus(shelf: shelf.id, card: ExploreCard.id))
        }
    }

    /// Scrolls to an offset, not to a card id: an id with a center anchor asked the
    /// near-start cards for an offset before the row's start. The scroll view clamped it
    /// while focus stayed, but re-applied the stored target when focus left for the tab
    /// bar and clamped it twice the inset over, shifting the row a third of a card.
    /// Cards have known widths, so the offset that places one is known exactly.
    private func scroll(to card: String) {
        guard let index = shelf.focusOrder.firstIndex(of: card), let containerWidth else { return }
        let x = metrics.offset(focusing: index, container: containerWidth)
        #if DEBUG
        Self.log.debug("row \(shelf.id) focus \(index) → x \(Int(x))")
        #endif
        scrollPosition.scrollTo(x: x)
    }

    #if DEBUG
    private static let log = AppLog(category: "home")
    #endif
}
