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

    /// The next title's backdrop, so it is decoded before it slides in.
    private func prefetchNext() {
        guard slides.count > 1, width > 0 else { return }
        let next = slides[(index + 1) % slides.count]
        ImagePipeline.prefetch(Artwork.url(next.backdropURL ?? next.artworkURL), size: tileSize)
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
                RemoteImage(url: logo, size: CGSize(width: 220, height: 70), contentMode: .fit,
                            alignment: .bottomLeading) { _ in
                    Text(card.title).font(.title2.bold())
                }
                .frame(width: 220, height: 70, alignment: .bottomLeading)
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
#endif
