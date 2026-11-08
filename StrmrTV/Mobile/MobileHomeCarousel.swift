#if os(iOS)
import SwiftUI

/// Home's Top Carousel on a phone: the TV's Top Carousel setting and row (Top 10, else
/// Trending, else the first row with titles; `HomeCarouselSource`), as a paged row of large
/// backdrop tiles with the title's logo and line. It moves on by itself every eight seconds
/// while Home is up; a swipe starts the eight seconds over.
struct MobileHomeCarousel: View {
    let shelf: HomeShelf
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var index = 0
    @State private var width: CGFloat = 0

    private var slides: [HomeCard] { HomeCarouselSource.slides(shelf) }

    /// Shorter on a wide screen (iPad), and a fixed strip on a phone on its side, so rows
    /// show under it.
    private var height: CGFloat {
        if verticalSizeClass == .compact { return 210 }
        let aspect: CGFloat = sizeClass == .regular ? 21 / 9 : 16 / 9
        return max(((width - 32) / aspect).rounded(), 1)
    }

    private var tileSize: CGSize { CGSize(width: max(width - 32, 1), height: height) }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(slides.enumerated()), id: \.element.id) { offset, card in
                MobileHomeHero(card: card, size: tileSize, pageCount: slides.count)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: slides.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .task(id: TimerKey(index: index, active: scenePhase == .active, count: slides.count)) {
            guard scenePhase == .active, slides.count > 1 else { return }
            try? await Task.sleep(for: HomeCarousel.interval)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { index = (index + 1) % slides.count }
        }
        .onChange(of: index) { prefetchNext() }
        .onChange(of: slides.count) { _, count in if index >= count { index = 0 } }
        .onAppear(perform: prefetchNext)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeCarousel")
    }

    private struct TimerKey: Equatable {
        let index: Int
        let active: Bool
        let count: Int
    }

    /// The neighbouring titles' backdrops and logos, so they are decoded before they slide
    /// in and a swipe either way lands on the logo rather than its text fallback.
    private func prefetchNext() {
        guard slides.count > 1, width > 0 else { return }
        for step in [1, slides.count - 1] {
            let card = slides[(index + step) % slides.count]
            ImagePipeline.prefetch(Artwork.url(card.backdropURL ?? card.artworkURL), size: tileSize)
            ImagePipeline.prefetch(Artwork.logoURL(card.logoURL, size: "w500"), size: MobileHeroLogo.size, mode: .fit)
        }
    }
}

/// One carousel page: the title's backdrop filling the tile, its logo (or name) and line
/// over a scrim at the foot. Tap and long press as `MobileCardLink`; the long press lifts
/// the tile itself, whole, over the page.
struct MobileHomeHero: View {
    let card: HomeCard
    let size: CGSize
    /// More than one shows the page dots under the text.
    var pageCount = 1

    private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        MobileCardLink(card: card, preview: AnyView(tile), previewCornerRadius: 14) { tile }
            .accessibilityIdentifier("homeHero")
    }

    private var tile: some View {
        RemoteImage(url: Artwork.url(card.backdropURL ?? card.artworkURL), size: size) { _ in
            Rectangle().fill(.quaternary)
        }
        .overlay {
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
        }
        .overlay(alignment: .bottomLeading) { info }
        .overlay(alignment: .bottom) {
            if ProgressBar.shows(card.progress) {
                MobileProgressBar(value: card.progress).padding(.horizontal, 16).padding(.bottom, 6)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Self.shape)
        .contentShape(Self.shape)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let logo = Artwork.logoURL(card.logoURL, size: "w500") {
                MobileHeroLogo(url: logo, title: card.title)
            } else {
                Text(card.title).font(.title2.bold())
            }
            Text(card.subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
        .padding(.horizontal, 16)
        // Clear of the page dots along the foot.
        .padding(.bottom, pageCount > 1 ? 30 : 16)
        .padding(.top, 16)
        .foregroundStyle(.white)
    }
}

/// A carousel title's logo in its fixed slot. While the logo loads the slot stays empty for
/// a short grace period rather than flashing the name first; the name shows only when there
/// is no logo, it failed, or it is still loading after the grace period.
struct MobileHeroLogo: View {
    let url: URL
    let title: String

    static let size = CGSize(width: 220, height: 70)
    private static let grace: Duration = .milliseconds(1200)

    @State private var graceOver = false

    var body: some View {
        RemoteImage(url: url, size: Self.size, contentMode: .fit, alignment: .bottomLeading) { failed in
            if failed || graceOver {
                Text(title).font(.title2.bold()).transition(.opacity)
            } else {
                Color.clear
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .bottomLeading)
        .animation(.easeOut(duration: 0.2), value: graceOver)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .task(id: url) {
            graceOver = false
            try? await Task.sleep(for: Self.grace)
            guard !Task.isCancelled else { return }
            graceOver = true
        }
    }
}
#endif
