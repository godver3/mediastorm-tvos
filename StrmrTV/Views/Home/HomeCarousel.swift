import SwiftUI

/// Home's Top Carousel: up to ten titles of one row, as on the Apple TV
/// app's home. This is its fixed layer: a backdrop filling the whole screen, edge to edge
/// whatever the TV's safe area, with the title's logo (or name), its year / kind / rating /
/// genre line and a short overview just above the buttons. The buttons and page dots
/// (`HomeCarouselControls`) are the page's first shelf, in the rows' scroll view. Going
/// Down into the rows this layer crossfades away (`shown`) as the buttons scroll up out of
/// sight; Up brings it back.
///
/// It moves on by itself every eight seconds, focused or not; any press on the remote
/// starts the eight seconds over. It stops while Home is covered or the app is away.
struct HomeCarousel: View {
    /// The carousel's focus identities: `HomeFocus(shelf: focusShelf, card: Control)`.
    static let focusShelf = "home-carousel"
    enum Control: String { case play, watchlist, info }
    static func focus(_ control: Control) -> HomeFocus { HomeFocus(shelf: focusShelf, card: control.rawValue) }

    static let interval: Duration = .seconds(8)
    static let log = AppLog(category: "home-carousel")

    let shelf: HomeShelf
    @Binding var index: Int
    /// Set when it moves on by itself (see `HomeCarouselControls.advancedAt`).
    @Binding var advancedAt: Date
    /// Up, rather than crossfaded away for focus in the rows.
    let shown: Bool
    let textScale: CGFloat
    /// Home is on screen and the app in the foreground: the only time it moves on.
    let isActive: Bool

    @ObservedObject private var remote = RemoteActivity.shared

    private var slides: [HomeCard] { HomeCarouselSource.slides(shelf) }
    private var current: HomeCard? { slides.indices.contains(index) ? slides[index] : slides.first }

    var body: some View {
        // Each title's text at its natural height, its foot on one line: a new title's
        // crossfades in over the old where it stands, and nothing moves.
        ZStack(alignment: .bottomLeading) {
            HomeCarouselInfo(card: current, rowTitle: shelf.title, textScale: textScale)
                .id(current?.id)
                .transition(.opacity)
        }
        .padding(.leading, 80)
        // Just above the buttons, which sit on the bottom safe area.
        .padding(.bottom, HomeCarouselControls.height + 30 * textScale)
        // The text keeps to the safe area top and bottom; sideways it lines up with
        // the rows' 80 pt margin from the screen edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .ignoresSafeArea(.container, edges: .horizontal)
        // The whole physical screen, safe area ignored on every edge, as Classic's hero
        // backdrop: aspect-fill, framed and cropped the same. Fixed: it only crossfades.
        .background {
            Backdrop(url: Artwork.url(current?.backdropURL), fade: 0.6)
                .overlay(scrim)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.5), value: current?.id)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(!shown)
        .observesRemoteActivity()
        .task(id: TimerKey(index: index, isActive: isActive, count: slides.count, presses: remote.count)) {
            guard isActive, slides.count > 1 else { return }
            try? await Task.sleep(for: Self.interval)
            guard !Task.isCancelled else { return }
            advancedAt = .now
            index = (index + 1) % slides.count
            Self.log.debug("auto-advance to \(index + 1)/\(slides.count)")
        }
        .onChange(of: index) { prefetchNext() }
        .onChange(of: slides.count) { _, count in if index >= count { index = 0 } }
        .onChange(of: shelf.id) { index = 0 }
        .onAppear(perform: prefetchNext)
    }

    private struct TimerKey: Equatable {
        let index: Int
        let isActive: Bool
        let count: Int
        let presses: Int
    }

    /// Darker toward the bottom, and from the left, behind the text, in an eased curve.
    /// The art still shows at the bottom edge: the backdrop runs to it.
    private var scrim: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: .clear, location: 0.4),
                .init(color: .black.opacity(0.12), location: 0.52),
                .init(color: .black.opacity(0.32), location: 0.66),
                .init(color: .black.opacity(0.52), location: 0.8),
                .init(color: .black.opacity(0.66), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.8), location: 0),
                .init(color: .black.opacity(0.35), location: 0.4),
                .init(color: .clear, location: 0.65),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// The next title's backdrop and logo, so they are decoded before the crossfade.
    private func prefetchNext() {
        guard slides.count > 1 else { return }
        let next = slides[(index + 1) % slides.count]
        ImagePipeline.prefetch(Artwork.url(next.backdropURL), size: UIScreen.main.bounds.size)
        ImagePipeline.prefetch(HomeCarouselInfo.logoURL(next), size: HomeCarouselInfo.logoBox(textScale), mode: .fit)
    }
}

extension EnvironmentValues {
    /// Opens a title's details over the Home view it was chosen on; set by the Home tab.
    @Entry var openHomeDetails: (DetailsTarget) -> Void = { _ in }
}
