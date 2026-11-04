import SwiftUI

extension HomeCard {
    /// "2024 · Movie · PG-13 · Action, Thriller": the Top Carousel's and an expanded
    /// card's line.
    var infoLine: String {
        let genres = genres.prefix(2).joined(separator: ", ")
        return [subtitle, certification ?? "", genres].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// An expanded poster's info (Settings › Home Layout › Show Info When Expanded): the
/// title's logo (else its name), its year / rating / genre line and overview over the
/// bottom of the 16:9 art, on a gradient dark enough to read against bright art, and
/// lifted clear of a progress bar.
struct ExpandedCardInfo: View {
    let card: HomeCard
    let size: CGSize
    let hasProgress: Bool

    /// Type scale for the card size (1 at the Large 270 pt card).
    private var scale: CGFloat { max(size.height / ShelfRow.baseCardHeight, 0.6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Spacer(minLength: 0)
            logo.padding(.bottom, 2 * scale)
            if !card.infoLine.isEmpty {
                Text(card.infoLine)
                    .font(.system(size: 19 * scale, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            if let overview = card.overview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 17 * scale))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 4)
        .padding(.horizontal, 20 * scale)
        .padding(.bottom, (hasProgress ? 30 : 16) * scale)
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .background(alignment: .bottom) {
            LinearGradient(stops: [.init(color: .clear, location: 0),
                                   .init(color: .black.opacity(0.55), location: 0.45),
                                   .init(color: .black.opacity(0.9), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: size.height * 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var logoBox: CGSize { CGSize(width: size.width * 0.45, height: size.height * 0.24) }

    /// The logo, else the name; nothing while the logo loads, so the name doesn't flash first.
    @ViewBuilder
    private var logo: some View {
        if let url = Artwork.logoURL(card.logoURL, size: "w500") {
            RemoteImage(url: url, size: logoBox, contentMode: .fit, alignment: .bottomLeading) { failed in
                if failed { name } else { Color.clear }
            }
        } else {
            name
        }
    }

    private var name: some View {
        Text(card.title)
            .font(.system(size: 28 * scale, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size.width * 0.8, height: logoBox.height, alignment: .bottomLeading)
    }
}
