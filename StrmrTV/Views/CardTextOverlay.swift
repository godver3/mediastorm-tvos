import SwiftUI

/// Where Home's cards draw their title and year / episode line (Settings › Home Layout).
enum CardText: String, CaseIterable, Identifiable, Sendable {
    /// Under the card.
    case below
    /// On the card's art, at the bottom over a gradient (the Expo TV home's text overlay).
    case overlay
    /// Over the art of 16:9 cards only (landscape rows and posters opened on focus); posters stay bare.
    case overlayWide
    /// Not drawn ("None"): more rows fit on screen.
    case off

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .below: "Below"
        case .overlay: "Overlay"
        case .overlayWide: "Overlay on Expanded"
        case .off: "None"
        }
    }

    /// Whether a card drawing its poster (or its 16:9 art) puts the text over it.
    func overlays(poster: Bool) -> Bool {
        self == .overlay || (self == .overlayWide && !poster)
    }
}

/// A card's title and line over the bottom of its art, as the Expo TV home draws them
/// (`landscapeCardTextContainer` / `cardTextContainer`): a clear → 70 % → 95 % black
/// gradient, the text left-aligned on 16:9 cards and centred on posters, and lifted
/// clear of a progress bar.
struct CardTextOverlay: View {
    let title: String
    let subtitle: String
    let size: CGSize
    let poster: Bool
    let hasProgress: Bool

    /// Type scale for the card size (1 at the Large 270 pt card).
    private var scale: CGFloat { max(size.height / ShelfRow.baseCardHeight, 0.6) }
    private var alignment: HorizontalAlignment { poster ? .center : .leading }

    var body: some View {
        VStack(alignment: alignment, spacing: 4 * scale) {
            Text(title)
                .font(.system(size: (poster ? 22 : 26) * scale, weight: .semibold))
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: (poster ? 18 : 21) * scale))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(poster ? .center : .leading)
        .padding(.horizontal, (poster ? 12 : 20) * scale)
        .padding(.top, 28 * scale)
        .padding(.bottom, (hasProgress ? (poster ? 28 : 36) : 16) * scale)
        .frame(width: size.width, alignment: Alignment(horizontal: alignment, vertical: .bottom))
        .frame(minHeight: size.height * (poster ? 0.4 : 0.5), alignment: .bottom)
        .background {
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0),
                                   .init(color: .black.opacity(0.7), location: 0.6),
                                   .init(color: .black.opacity(0.95), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}
