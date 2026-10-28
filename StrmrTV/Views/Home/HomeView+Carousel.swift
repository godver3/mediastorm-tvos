import SwiftUI

/// Home other than Classic: Classic's rows, with the Top Carousel on top
/// of the page when it is on. The carousel is the page's "hero and first shelf": its art
/// and title text are a fixed layer (`HomeCarousel`), and its buttons and dots
/// (`HomeCarouselControls`) are the first place in the rows' scroll view, one viewport tall
/// with the buttons on the bottom safe area. Down from them scrolls the first row into
/// Classic's place exactly as one row scrolls to the next (with the full hero, fades to it, as
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

    /// The carousel's controls, near the foot of a stretch one viewport tall: at rest they
    /// sit on the bottom safe area (the rows' viewport ends there with the full hero, and runs
    /// to the screen's edge otherwise) and the first row waits just out of sight below. The
    /// stretch runs `focusRoom` past the viewport, under the buttons, so a focused button's
    /// growth and shadow are drawn there (see `carouselClip`) rather than cut off.
    @ViewBuilder
    func carouselSlot(size: HeroSize) -> some View {
        if let shelf = carouselSource.shelf {
            Color.clear
                .containerRelativeFrame(.vertical) { length, _ in length + HomeCarouselControls.focusRoom }
                .overlay(alignment: .bottomLeading) {
                    HomeCarouselControls(shelf: shelf, focused: $focused, index: $carouselIndex,
                                         entry: carouselButton, advancedAt: carouselAdvancedAt)
                        // The scroll view's content keeps to the 80 pt side safe area already.
                        .padding(.bottom, (size == .full ? 0 : safeBottom) + HomeCarouselControls.focusRoom)
                }
                .id(Self.carouselSlotID)
        }
    }

    /// The rows' scroll view clips to its viewport, except, while the carousel is up, for
    /// `focusRoom` below it and to either side: the room around the carousel's buttons, which
    /// with the full hero falls on the bottom safe area. Without the carousel up it is the plain
    /// clip, so the next row never peeks below the focused one.
    @ViewBuilder
    func carouselClip(_ rows: some View, carousel: Bool) -> some View {
        if carousel {
            rows.scrollClipDisabled()
                .mask(alignment: .top) {
                    Rectangle()
                        .padding(.bottom, carouselShown ? -HomeCarouselControls.focusRoom : 0)
                        // Play sits on the viewport's leading edge; its focus growth needs room there too.
                        .padding(.horizontal, carouselShown ? -HomeCarouselControls.focusRoom : 0)
                }
        } else {
            rows
        }
    }
}
