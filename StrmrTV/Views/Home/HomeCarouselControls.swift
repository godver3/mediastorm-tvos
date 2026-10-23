import SwiftUI

/// The Top Carousel's Play, Watchlist and Details buttons and its page dots.
/// They are the page's first "shelf": they sit in the rows' scroll view,
/// above the first row, and scroll away and back exactly as one row does in Classic.
///
/// Left on Play and Right on Details step to the previous / next title (wrapping). Not with
/// `onMoveCommand`, which takes every arrow press from the button it is on, so focus could
/// never move between the buttons (and a swipe on the remote's touch surface never sends one
/// anyway): an invisible stop either side of the buttons takes focus for an instant instead,
/// steps the title and hands focus straight back. With the side menu, Left on Play on the
/// first title still opens the menu.
struct HomeCarouselControls: View {
    typealias Control = HomeCarousel.Control

    let shelf: HomeShelf
    var focused: FocusState<HomeFocus?>.Binding
    @Binding var index: Int
    /// The button focus enters on: the one last used, else Play.
    let entry: HomeFocus?
    /// When the carousel last moved on by itself: Select is ignored for a second after, so a
    /// press can't act on a title that changed under it.
    let advancedAt: Date

    @EnvironmentObject private var watchlist: WatchlistStore
    @Environment(\.openHomeDetails) private var openDetails
    @Environment(\.sidebarInset) private var sidebarInset
    @State private var watchlistBusy = false

    /// The controls' height: the buttons' unfocused height.
    static let height: CGFloat = 66
    /// How far a focused button reaches below its resting frame (its growth and shadow);
    /// the rows' scroll view leaves this much room under the controls.
    static let focusRoom: CGFloat = 40
    /// The invisible stops either side of the buttons.
    static let previous = HomeFocus(shelf: HomeCarousel.focusShelf, card: "previous")
    static let next = HomeFocus(shelf: HomeCarousel.focusShelf, card: "next")

    private var slides: [HomeCard] { HomeCarouselSource.slides(shelf) }
    private var current: HomeCard? { slides.indices.contains(index) ? slides[index] : slides.first }

    var body: some View {
        ZStack(alignment: .trailing) {
            buttons
            dots
        }
        .frame(height: Self.height)
        .onChange(of: focused.wrappedValue) { _, focus in
            if focus == Self.previous { step(by: -1, back: .play) }
            if focus == Self.next { step(by: 1, back: .info) }
        }
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 28) {
            Button { act("play", play) } label: {
                Label((current?.progress ?? 0) > 0 ? String(localized: "Resume") : String(localized: "Play"),
                      systemImage: "play.fill")
            }
            .focused(focused, equals: HomeCarousel.focus(.play))
            .overlay(alignment: .leading) {
                stop(Self.previous, after: .play, enabled: slides.count > 1 && (sidebarInset == 0 || index > 0))
                    .alignmentGuide(.leading) { $0[.trailing] + 14 }
            }

            let inWatchlist = current?.target.map { watchlist.contains($0, server: nil) } ?? false
            Button { act("watchlist", toggleWatchlist) } label: {
                Label(inWatchlist ? String(localized: "In Watchlist") : String(localized: "Add to Watchlist"),
                      systemImage: inWatchlist ? "checkmark" : "plus")
                    .labelStyle(.iconOnly)
            }
            .focused(focused, equals: HomeCarousel.focus(.watchlist))
            .accessibilityHint(inWatchlist ? "Removes this title from your watchlist" : "Adds this title to your watchlist")

            Button { act("details", openInfo) } label: {
                Label("Details", systemImage: "info.circle").labelStyle(.iconOnly)
            }
            .focused(focused, equals: HomeCarousel.focus(.info))
            .overlay(alignment: .trailing) {
                stop(Self.next, after: .info, enabled: slides.count > 1)
                    .alignmentGuide(.trailing) { $0[.leading] - 14 }
            }
        }
        // Up from any card of the first row lands here, on the button last used: the
        // section spans the screen, so a card far to the right still finds it.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .defaultFocus(focused, entry, priority: .userInitiated)
        .accessibilityHint(Text("Left on Play and right on Details change the title"))
    }

    /// An invisible stop beside `control`, focusable only while that button has focus (so
    /// Up from the rows can't land on it) or while it has focus itself.
    private func stop(_ id: HomeFocus, after control: Control, enabled: Bool) -> some View {
        let here = focused.wrappedValue == id
        return Color.clear
            .frame(width: 2, height: Self.height)
            .focusable(here || enabled && focused.wrappedValue == HomeCarousel.focus(control))
            .focused(focused, equals: id)
            .accessibilityHidden(true)
    }

    private func step(by offset: Int, back control: Control) {
        if slides.count > 1 {
            index = (index + offset + slides.count) % slides.count
            HomeCarousel.log.debug("step to \(index + 1)/\(slides.count)")
        }
        // After the focus update that brought focus here: a change made during it is lost,
        // or leaves the button drawn unfocused.
        DispatchQueue.main.async { focused.wrappedValue = HomeCarousel.focus(control) }
    }

    /// Runs a button's action, unless the title changed by itself under the press.
    private func act(_ name: String, _ action: () -> Void) {
        guard Date.now.timeIntervalSince(advancedAt) >= 1 else {
            HomeCarousel.log.info("\(name) ignored: the title changed under the press")
            return
        }
        action()
    }

    /// As the details page's Play: opens the title's details, which start what Play there
    /// would (resume, or the next episode) once they load.
    private func play() {
        guard let target = current?.target else { return }
        HomeCarousel.log.info("play \(target.titleID) from \(shelf.id)")
        DeepLinkRouter.shared.armAutoplay(target.titleID)
        openDetails(target)
    }

    private func openInfo() {
        guard let target = current?.target else { return }
        HomeCarousel.log.info("details \(target.titleID) from \(shelf.id)")
        openDetails(target)
    }

    /// Repeat presses while a change is in flight are ignored.
    private func toggleWatchlist() {
        guard let target = current?.target, !watchlistBusy else { return }
        watchlistBusy = true
        let adding = !watchlist.contains(target, server: nil)
        Task {
            defer { watchlistBusy = false }
            do {
                if adding { try await watchlist.add(target) } else { try await watchlist.remove(target) }
                HomeCarousel.log.info("watchlist \(adding ? "add" : "remove") \(target.titleID)")
            } catch {
                HomeCarousel.log.error("watchlist \(adding ? "add" : "remove") \(target.titleID) failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Dots

    private var dots: some View {
        HStack(spacing: 12) {
            ForEach(slides.indices, id: \.self) { slide in
                Capsule()
                    .fill(.white.opacity(slide == index ? 0.95 : 0.35))
                    .frame(width: slide == index ? 30 : 10, height: 10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: index)
        .opacity(slides.count > 1 ? 1 : 0)
        .accessibilityElement()
        .accessibilityLabel(Text("Title \(index + 1) of \(slides.count)"))
    }
}
