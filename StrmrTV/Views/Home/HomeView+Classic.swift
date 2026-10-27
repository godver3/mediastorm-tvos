import SwiftUI

/// Classic Home: the focus-driven hero over the rows.
extension HomeView {
    // The hero has a fixed frame and the rows scroll only from row to row, so moving
    // focus along a row never shifts the page.
    var classicPage: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackdrop
            rowsPage(size: heroSize, carousel: false)
        }
    }

    /// Classic's hero text over its rows, laid out at `size` (`.off` for rows alone). Also
    /// the rows of a Top Carousel page (`carousel`), under the carousel's controls, which
    /// scroll away as one row does and leave the first row, whole, in Classic's place.
    func rowsPage(size: HeroSize, carousel: Bool) -> some View {
        // A one-screen scroll view that never scrolls: the tab bar's focus hand-off
        // needs a scroll view at the top of the content, but nothing may move.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: size == .off ? 0 : 36) {
                if size == .full { Spacer(minLength: 0) }
                if size != .off {
                    // Mid-swap, the row fading out keeps its title's info.
                    HeroInfo(hero: hero(swapFrom) ?? hero, size: size, textScale: layout.heroTextSize.scale)
                        .opacity(carousel && carouselShown ? 0 : 1)
                }

                VStack(alignment: .leading, spacing: 0) {
                    rowEntryGuide
                    rows(size: size, carousel: carousel)
                }
                // Full hero: exactly the shown row's height, so that shelf sits on the
                // bottom edge and the row under it never shows. Smaller: every bit of height
                // left, so more rows show.
                .frame(height: size == .full ? rowHeight : nil, alignment: .top)
                .frame(maxHeight: size == .full ? nil : .infinity, alignment: .top)
            }
            // The full hero swaps rows by fading the page out and back (see `rows`).
            .opacity(size == .full ? rowFade : 1)
            .padding(.top, size == .full ? 0 : Self.tabBarClearance)
            .padding(.horizontal, 80)
            .containerRelativeFrame(.vertical, alignment: .bottomLeading)
        }
        .scrollDisabled(true)
        .scrollClipDisabled()
        // With a smaller hero the rows run to the screen's bottom edge, as a
        // scrolling list does, so the row below shows more of itself.
        .ignoresSafeArea(.container, edges: size == .full ? [] : .bottom)
    }

    /// The focused card's backdrop (or a streaming service's framed logo), darkened where
    /// the rows begin and behind the text. Classic's, and Focused Title Info's under a carousel.
    var heroBackdrop: some View {
        Backdrop(url: Artwork.url(hero?.backdropURL), settle: HomeView.artSettle)
            .overlay(alignment: .topTrailing) {
                if heroSize != .off, let logo = hero?.framedLogoURL {
                    FramedHeroLogo(url: Artwork.logoURL(logo), scale: heroSize.framedLogoScale)
                        .id(logo)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: hero?.framedLogoURL)
            .overlay(
                // Darker from about where the rows start, so a smaller hero (more
                // rows) still has the rows on black.
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.05), location: 0),
                    .init(color: .black.opacity(0.55), location: rowsTop),
                    .init(color: .black.opacity(0.95), location: rowsTop + 0.3),
                    .init(color: .black, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .leading, endPoint: .center)
            )
            .ignoresSafeArea()
    }

    /// An invisible full-width strip above the rows. Down from the tab bar lands here
    /// rather than on whichever card sits under the tab, and it hands focus straight to
    /// the remembered card, so no wrong card lights up first. It only takes focus while
    /// the rows have none, so Up from a card still reaches the tab bar.
    var rowEntryGuide: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 2, maxHeight: 2)
            .focusable(focused == nil && !shelves.isEmpty)
            .focused($guideFocused)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rows(size: HeroSize, carousel: Bool) -> some View {
        // The carousel's row shows as the carousel, not again among the rows.
        let source = carouselSource.id
        let slots = store.slots.filter { $0.id != source }
        // Placeholders alone are worth showing only while some row is still on its way;
        // nothing loaded and nothing coming is the page's error.
        if !carousel && (slots.isEmpty || (shelves.isEmpty && !slots.contains(where: \.isLoading))) {
            homeStatus
        } else {
            // Each row is exactly one row-height tall and the focused row is scrolled to the
            // top, so it always sits in the same place under the hero. The focus engine may
            // not scroll this view itself: it also scrolls ancestors on a sideways move,
            // which threw the rows back to the first one. Rows move only when focus
            // changes row.
            // Not lazy: the scroll view never scrolls by itself, so Down only finds the
            // next row if it is already built; building every row up front also lets each
            // row's art load before focus reaches it. The rows themselves are lazy, so
            // that is a few cards per row. A row still loading holds its place, so it
            // arrives without pushing the rows below it down.
            ScrollViewReader { proxy in
                carouselClip(ScrollView(.vertical) {
                    let menuFocus = menuFocus
                    VStack(alignment: .leading, spacing: 0) {
                        if carousel { carouselSlot(size: size) }
                        ForEach(slots) { slot in
                            slotRow(slot, cardHeight: cardHeight(forShelf: slot.id), menuFocus: menuFocus)
                            .frame(height: rowHeight(forShelf: slot.id), alignment: .top)
                            .id(slot.id)
                        }
                    }
                }, carousel: carousel)
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
                .onChange(of: focused?.shelf) { old, shelf in
                    guard let shelf else { return }
                    // The carousel's controls are the first place, and move as a row does.
                    let place = shelf == HomeCarousel.focusShelf ? Self.carouselSlotID : shelf
                    let carouselMove = [old, shelf].contains(HomeCarousel.focusShelf)
                    if size == .full && !carouselMove && old != nil {
                        // The full hero is one shelf to a screen: from row to row the page fades
                        // out, the next row (and its height) takes its place, and it fades back
                        // in, rather than the rows sliding up or down.
                        let left = old.flatMap { old in rowFocus[old].map { HomeFocus(shelf: old, card: $0) } }
                        swapRow(from: left, to: shelf) { proxy.scrollTo(place, anchor: .top) }
                    } else {
                        withAnimation(Self.shelfScroll) {
                            shownRow = shelf
                            proxy.scrollTo(place, anchor: .top)
                        }
                    }
                }
                // A row arriving (or emptying) above the focused one would shift it; put
                // the focused row back in its place.
                .onChange(of: (carousel ? [Self.carouselSlotID] : []) + slots.map(\.id)) {
                    let shelf = carousel && carouselShown ? Self.carouselSlotID : focused?.shelf ?? heroFocus?.shelf
                    guard let shelf else { return }
                    proxy.scrollTo(shelf, anchor: .top)
                }
            }
            // Full screen width so the rows' horizontal scroll views keep their margins.
            .padding(.horizontal, -80)
        }
    }

    /// The full hero's move from row to row: fade out, put `shelf` in place unanimated, fade in.
    /// A move made mid-fade takes over, so a held Down lands on the last row reached.
    private func swapRow(from left: HomeFocus?, to shelf: String, place: @escaping () -> Void) {
        if swapFrom == nil { swapFrom = left }
        rowSwap.restart {
            withAnimation(.easeIn(duration: Self.rowFadeOut)) { rowFade = 0 }
            try? await Task.sleep(for: .seconds(Self.rowFadeOut))
            guard !Task.isCancelled else { return }
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                shownRow = shelf
                swapFrom = nil
                place()
            }
            withAnimation(.easeOut(duration: Self.rowFadeIn)) { rowFade = 1 }
        }
    }

    static let rowFadeOut = 0.12
    static let rowFadeIn = 0.2

    /// Roughly where the rows start, as a fraction of the screen height.
    private var rowsTop: CGFloat {
        switch heroSize {
        case .full: 0.5
        case .compact: 0.4
        case .minimal: 0.3
        case .off: 0.2
        }
    }

    /// What Home shows with no rows: loading, the load's error, or an empty page.
    @ViewBuilder
    var homeStatus: some View {
        if store.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
        } else if let loadError = store.loadError {
            Text(loadError).foregroundStyle(.secondary)
        } else {
            Text(store.view == HomeViews.all ? "Nothing here yet. Find something in Search."
                 : "Nothing on this page yet.").foregroundStyle(.secondary)
        }
    }

    /// One place on Home: a row of cards at `cardHeight`, or a placeholder holding its place.
    @ViewBuilder
    func slotRow(_ slot: HomeSlot, cardHeight: CGFloat, menuFocus: HomeFocus?) -> some View {
        switch slot {
        case let .shelf(shelf) where shelf.id == HomeShelf.promotedTopTenID:
            PromotedTopTenRow(shelf: shelf, focused: $focused, index: $promotedIndex, cardHeight: cardHeight)
        case let .shelf(shelf):
            ShelfRow(shelf: shelf, focused: $focused, entry: entry(shelf),
                     focusedCard: focused?.shelf == shelf.id ? focused?.card : nil,
                     menuCard: menuFocus?.shelf == shelf.id ? menuFocus?.card : nil,
                     position: layout.effectiveFocusPosition,
                     style: layout.style(for: shelf.id), cardHeight: cardHeight,
                     cardText: layout.effectiveCardText,
                     onHide: shelf.id == HomeShelf.continueWatchingID ? { hide($0) } : nil)
                .equatable()
        case let .loading(id, title), let .failed(id, title):
            PlaceholderRow(id: id, title: title, failed: !slot.isLoading,
                           style: layout.style(for: id), cardHeight: cardHeight, focused: $focused)
        }
    }
}
