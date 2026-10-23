import SwiftUI
import UIKit

/// The Top Carousel's text for one title: the row it comes from, the logo or name, the
/// year / kind / rating / genre line and the overview. One stack at its natural height,
/// sized by what the title has: a short overview or a low logo makes the block shorter,
/// and the carousel keeps its foot just above the buttons, so it closes up from the top.
struct HomeCarouselInfo: View {
    let card: HomeCard?
    let rowTitle: String
    let textScale: CGFloat

    /// The box a logo fits in, keeping its shape: a wide logo is as wide as this, a tall
    /// one as tall.
    static func logoBox(_ textScale: CGFloat) -> CGSize { CGSize(width: 640 * textScale, height: 170 * textScale) }
    static func logoURL(_ card: HomeCard?) -> URL? { Artwork.logoURL(card?.logoURL, size: "w500") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * textScale) {
            Text(eyebrow)
                .font(.system(size: 22 * textScale, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.7))
            HomeCarouselLogo(url: Self.logoURL(card), box: Self.logoBox(textScale)) {
                Text(card?.title ?? " ")
                    .font(.system(size: 68 * textScale, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 940 * textScale, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel(card?.title ?? "")
            if !line.isEmpty {
                Text(line)
                    .font(.system(size: 26 * textScale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            if let overview = card?.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 25 * textScale))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                    .frame(maxWidth: 940 * textScale, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 8)
    }

    /// "Top 10 Today · #3", or the row's name.
    private var eyebrow: String {
        guard let badge = card?.badge?.text, badge.hasPrefix("#") else { return rowTitle }
        return "\(rowTitle) · \(badge)"
    }

    /// "2024 · Movie · PG-13 · Action, Thriller"
    private var line: String {
        guard let card else { return "" }
        let genres = card.genres.prefix(2).joined(separator: ", ")
        return [card.subtitle, card.certification ?? "", genres].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A title's logo at its own shape, as large as fits `box`, rather than in a fixed slot:
/// a low, wide logo takes only its own height. Falls back to the name with no logo, a
/// failed load, or a load slower than the grace period; holds the box's height until then.
private struct HomeCarouselLogo<Fallback: View>: View {
    let url: URL?
    let box: CGSize
    @ViewBuilder let fallback: () -> Fallback

    @State private var image: UIImage?
    @State private var failed = false
    @State private var graceOver = false

    init(url: URL?, box: CGSize, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.url = url
        self.box = box
        self.fallback = fallback
        // Prefetched with the slide before it, so it is usually drawn at once.
        _image = State(initialValue: ImagePipeline.cached(url, size: box, mode: .fit))
    }

    var body: some View {
        Group {
            if let image, image.size.width > 0, image.size.height > 0 {
                let fit = min(box.width / image.size.width, box.height / image.size.height)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * fit, height: image.size.height * fit)
            } else if url == nil || failed || graceOver {
                fallback()
            } else {
                Color.clear.frame(width: 1, height: box.height)
            }
        }
        .task(id: url) {
            guard let url, image == nil else { return }
            async let loaded = ImagePipeline.load(url, size: box, mode: .fit, scale: ImagePipeline.scale)
            let grace = Task { try? await Task.sleep(for: .seconds(1.5)); if !Task.isCancelled { graceOver = true } }
            let result = await loaded
            grace.cancel()
            image = result
            failed = result == nil
        }
    }
}
