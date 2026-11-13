import SwiftUI

/// Home other than Classic: Classic's rows, with the Top Carousel on top
/// of the page when it is on. The carousel is the page's "hero and first shelf": its art
/// and title text are a fixed layer (`HomeCarousel`), and its buttons and dots
/// (`HomeCarouselControls`) are the first place in the rows' scroll view, one viewport tall
/// with the buttons on the bottom safe area. Down from them scrolls the first row into
/// Classic's place exactly as one row scrolls to the next (one shelf to a screen with Swap, fades to it, as
/// one row fades to the next), while the carousel's art
/// crossfades to the focused card's backdrop (Focused Title Info on) or the page's black,
/// and its text to the card's (or away). Up from the first row brings it all back.
extension HomeView {
    /// The first place in the rows' scroll view under a carousel: its controls.
    static let carouselSlotID = "home-carousel-slot"
    /// The scroll between the carousel's controls and the rows, and between rows, and the
    /// crossfade that goes with it.
    static let shelfScroll = Animation.easeInOut(duration: 0.3)

    /// The carousel's row; empty with Top Carousel off.
    var carouselSource: HomeCarouselSource {
        style.topCarousel ? .resolve(slots: store.slots, chosen: style.carouselRow) : HomeCarouselSource()
    }

    /// Where focus goes on entering the page from the tab bar: the carousel's button last
    /// used, else Play; with no carousel (or focus left in the rows), the rows.
    var carouselEntry: HomeFocus? {
        guard carouselSource.shelf != nil, carouselShown else { return rememberedFocus }
        return carouselButton
    }

    /// The carousel's button last used, else Play: where focus lands on coming back up.
    var carouselButton: HomeFocus {
        HomeCarousel.focus(rowFocus[HomeCarousel.focusShelf].flatMap(HomeCarousel.Control.init(rawValue:)) ?? .play)
    }

    var stackedPage: some View {
        let shelf = carouselSource.shelf
        let info = style.focusedInfo && shelf != nil
        let up = shelf != nil && carouselShown
        return ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            // The focused card's backdrop, which the carousel's crossfades to with the info on.
            if info { heroBackdrop.opacity(up ? 0 : 1) }
            if let shelf {
                HomeCarousel(shelf: shelf, index: $carouselIndex, advancedAt: $carouselAdvancedAt, shown: up,
                             textScale: layout.heroTextSize.scale,
                             controlsLift: carouselControlsLift(size: info ? heroSize : .off),
                             isActive: !isCovered && scenePhase == .active)
            }
            rowsPage(size: info ? heroSize : .off, carousel: shelf != nil)
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { safeBottom = $0 }
        // The page never scrolls, but the tab bar (or the side menu's pill) stays up regardless.
        .pinsTabBar()
        .onChange(of: focused) { _, focus in
            guard let focus else { return }
            let onCarousel = focus.shelf == HomeCarousel.focusShelf
            if onCarousel != carouselShown {
                withAnimation(Self.shelfScroll) { carouselShown = onCarousel }
            }
        }
    }

    /// Peek Next Row: how much of the first row shows under the carousel's buttons at rest (its
    /// top half); 0 with the setting off, when the row sits just out of sight.
    var carouselPeek: CGFloat {
        guard style.peekNextRow, let first = store.slots.first(where: { $0.id != carouselSource.id }) else { return 0 }
        return (rowHeight(forShelf: first.id) / 2).rounded()
    }

    /// How far above the bottom safe area the carousel's buttons sit, so its text stays just
    /// above them: 0 without Peek Next Row; with it, the peeking row and the room under the
    /// buttons, from the rows' viewport foot (the bottom safe area under hero text, else the screen's edge).
    func carouselControlsLift(size: HeroSize) -> CGFloat {
        let peek = carouselPeek
        guard peek > 0 else { return 0 }
        return max(0, peek + HomeCarouselControls.focusRoom - (size.oneShelf ? 0 : safeBottom))
    }

    /// The carousel's controls, near the foot of a stretch one viewport tall: at rest they
    /// sit on the bottom safe area (the rows' viewport ends there under hero text, and runs
    /// to the screen's edge otherwise) and the first row waits just out of sight below. The
    /// stretch runs `focusRoom` past the viewport, under the buttons, so a focused button's
    /// growth and shadow are drawn there (see `carouselClip`) rather than cut off. With Peek
    /// Next Row the stretch is `carouselPeek` short of the viewport instead, so the first row's
    /// top half shows under the buttons, `focusRoom` below them.
    @ViewBuilder
    func carouselSlot(size: HeroSize) -> some View {
        if let shelf = carouselSource.shelf {
            let peek = carouselPeek
            // Under hero text the viewport is the shown row's height, so it changes from row
            // to row; the stretch must not, or every row under it moves as focus changes row,
            // and a scroll aimed before the move lands a short row's title above the viewport
            // and the next row's title in it. It is the viewport it fills, the tallest row's.
            let fixed = size.oneShelf ? tallestRowHeight : nil
            Color.clear
                .containerRelativeFrame(.vertical) { length, _ in
                    let length = fixed ?? length
                    return peek > 0 ? length - peek : length + HomeCarouselControls.focusRoom
                }
                .overlay(alignment: .bottomLeading) {
                    HomeCarouselControls(shelf: shelf, focused: $focused, index: $carouselIndex,
                                         entry: carouselButton, advancedAt: carouselAdvancedAt)
                        // Inside the side safe area by the rows' margin, as their titles are.
                        .padding(.horizontal, HomeCarouselControls.margin)
                        .padding(.bottom, (size.oneShelf || peek > 0 ? 0 : safeBottom) + HomeCarouselControls.focusRoom)
                }
                .id(Self.carouselSlotID)
        }
    }

    /// The rows' scroll view clips to its viewport, except, while the carousel is up, for
    /// `focusRoom` below it: the room under the carousel's buttons, which under hero text
    /// falls on the bottom safe area. Without the carousel up it is the plain clip, so the next
    /// row never peeks below the focused one. With Peek Next Row the buttons sit inside the
    /// viewport, and the peeking row runs on to the screen's bottom edge: under hero text the
    /// viewport ends on the bottom safe area, and clipped there the row stopped short of the
    /// edge with the carousel's art showing under it.
    @ViewBuilder
    func carouselClip(_ rows: some View, carousel: Bool, size: HeroSize) -> some View {
        if carousel {
            let overflow = !carouselShown ? 0
                : carouselPeek > 0 ? (size.oneShelf ? safeBottom : 0)
                : HomeCarouselControls.focusRoom
            rows.scrollClipDisabled()
                .mask(alignment: .top) {
                    Rectangle()
                        .padding(.bottom, -overflow)
                        // To the screen's sides: the scroll view runs edge to edge, but a shape
                        // keeps out of the 80 pt side safe area, and cut the rows' cards off
                        // there as they scrolled.
                        .ignoresSafeArea(.container, edges: .horizontal)
                }
        } else {
            rows
        }
    }
}
