import SwiftUI

/// The hero's text and art: from a card, or from an explore card (the row's name).
struct HeroContent: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var overview: String?
    var backdropURL: String?
    var logoURL: String?
    /// A streaming service's (or art-less hub's) logo, drawn large at the top right on
    /// black in place of a backdrop, as the Expo home does; the title is then the name.
    var framedLogoURL: String?

    init(_ card: HomeCard) {
        id = card.id
        title = card.title
        subtitle = card.subtitle
        overview = card.overview
        backdropURL = card.backdropURL
        if card.logoTile, card.backdropURL == nil {
            framedLogoURL = card.logoURL
        } else {
            logoURL = card.logoURL
        }
    }

    init(explore: ExploreCard) {
        id = "\(explore.shelf)/\(ExploreCard.id)"
        title = explore.title
        subtitle = String(localized: "\(explore.total) titles")
        overview = String(localized: "See the whole list, including \(explore.moreCount) not shown here.")
        backdropURL = explore.backdropURL
        logoURL = nil
    }
}

/// A logo standing in for the hero's backdrop, contained in a fixed frame at the top
/// right (the Expo home's streaming-service hero: 0.9 × 0.4 screen heights, inset 48).
struct FramedHeroLogo: View {
    let url: URL?
    let scale: CGFloat

    var body: some View {
        let inset = 48 * scale
        RemoteImage(url: url, size: CGSize(width: (972 - 96) * scale, height: (432 - 96) * scale),
                    contentMode: .fit) { _ in Color.clear }
            .padding(inset)
            .padding(.top, 120 * scale)
            .padding(.trailing, 110 * scale)
            .accessibilityHidden(true)
    }
}

extension HeroSize {
    /// The framed logo's size against the full hero's.
    var framedLogoScale: CGFloat {
        switch self {
        case .full: 1
        case .compact: 0.75
        case .minimal, .off: 0.5
        }
    }
}

struct HeroInfo: View {
    let hero: HeroContent?
    let size: HeroSize
    let textScale: CGFloat

    /// Each size's block, at medium text; the block has a fixed height, so the rows
    /// never move as the overview's length changes.
    private var metrics: (height: CGFloat, logo: CGSize, title: CGFloat, line: CGFloat, overview: CGFloat, lines: Int) {
        switch size {
        case .full: (340, CGSize(width: 640, height: 150), 64, 28, 26, 3)
        case .compact: (210, CGSize(width: 420, height: 90), 48, 24, 22, 2)
        case .minimal, .off: (100, .zero, 44, 24, 0, 0)
        }
    }

    var body: some View {
        let m = metrics
        // The block sits in a fixed-height frame anchored at the bottom, so the rows never
        // move and a shorter overview leaves space above the logo, not above the rows.
        VStack(alignment: .leading, spacing: 14 * textScale) {
            if m.logo == .zero {
                titleText(size: m.title)
            } else {
                titleArea(logo: CGSize(width: m.logo.width * textScale, height: m.logo.height * textScale),
                          titleSize: m.title)
            }
            Text(hero?.subtitle ?? " ")
                .font(.system(size: m.line * textScale, weight: .medium))
                .lineLimit(1)
            if m.lines > 0 {
                Text(hero?.overview ?? " ")
                    .font(.system(size: m.overview * textScale))
                    .foregroundStyle(.secondary)
                    .lineLimit(m.lines)
                    .frame(maxWidth: 1000 * max(textScale, 1), alignment: .leading)
            }
        }
        .frame(height: m.height * textScale, alignment: .bottomLeading)
        .animation(nil, value: hero?.id)
    }

    /// The title's logo when the server sends one, else the name. The slot has a fixed
    /// size; bottom-left, so a short logo sits on the subtitle as the title text does.
    private func titleArea(logo: CGSize, titleSize: CGFloat) -> some View {
        TitleLogo(url: Artwork.logoURL(hero?.logoURL, size: "w500"), size: logo) { titleText(size: titleSize) }
            .frame(width: logo.width, height: logo.height, alignment: .bottomLeading)
            .accessibilityLabel(hero?.title ?? "")
    }

    private func titleText(size: CGFloat) -> some View {
        Text(hero?.title ?? " ")
            .font(.system(size: size * textScale, weight: .bold))
            .lineLimit(1)
    }
}
