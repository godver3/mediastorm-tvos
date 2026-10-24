import SwiftUI

/// A titled card of a game's page (Expo `sportsDetailPanel` and its heading): a dark
/// surface with the title, an optional note under it, then the panel's rows.
struct SportsPanel<Content: View>: View {
    let title: String?
    var note: String?
    @ViewBuilder let content: Content

    init(_ title: String?, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || note != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let title { Text(title).font(.headline).accessibilityAddTraits(.isHeader) }
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.bottom, 4)
            }
            content
        }
        .font(.callout)
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

extension View {
    /// A stop the remote can land on to read a row or block (Expo `SportsReadout`): the page
    /// scrolls to it, and it shows the focused TV card's white hairline. The highlight
    /// reaches past the content, so text stays lined up with the panel's title. A
    /// `.focused(_:equals:)` after it binds the stop.
    func sportsReadout(fill: Bool = true) -> some View {
        frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(SportsReadoutHighlight())
            .contentShape(SportsReadoutHighlight.shape)
            .accessibilityElement(children: .combine)
            .focusable()
            .focusEffectDisabled()
            .padding(.horizontal, -14)
    }

    /// A row of chips (tabs, sides, filters) as one focus section across the page, so Up and
    /// Down reach it from anywhere above or below; pair with `.defaultFocus(…, .userInitiated)`
    /// to land on the chosen chip.
    func sportsChipRow(alignment: Alignment = .leading) -> some View {
        fixedSize().frame(maxWidth: .infinity, alignment: alignment).focusSection()
    }
}

/// The focused readout's faint fill and hairline.
private struct SportsReadoutHighlight: View {
    static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Self.shape.fill(Color.white.opacity(isFocused ? 0.1 : 0))
            .overlay {
                Self.shape.strokeBorder(PosterFocusStyle.ringColor, lineWidth: PosterFocusStyle.ringWidth).opacity(isFocused ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// A readout that does something on Select (a drive to open, a player to look up): the focused
/// one gets the TV card's white hairline over a faint fill, like `.sportsReadout()`; a chosen
/// one keeps a fill while the remote is elsewhere, and a tinted one (the drive in progress)
/// takes the hub's live red.
struct SportsReadoutButtonStyle: ButtonStyle {
    var chosen = false
    var tinted = false

    func makeBody(configuration: Configuration) -> some View {
        ReadoutBody(configuration: configuration, chosen: chosen, tinted: tinted)
    }

    private struct ReadoutBody: View {
        let configuration: Configuration
        let chosen: Bool
        let tinted: Bool
        @Environment(\.isFocused) private var focused

        private static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        var body: some View {
            configuration.label
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Self.shape.fill(fill))
                .overlay {
                    Self.shape.strokeBorder(PosterFocusStyle.ringColor, lineWidth: PosterFocusStyle.ringWidth).opacity(focused ? 1 : 0)
                }
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
                .accessibilityAddTraits(chosen ? .isSelected : [])
        }

        private var fill: Color {
            if tinted { return SportsStatusPill.live.opacity(chosen ? 0.26 : 0.14) }
            return Color.white.opacity(chosen ? 0.14 : focused ? 0.1 : 0)
        }
    }
}

/// Columns sharing the width by weight (Expo's `flex` columns, `SportsOverviewLayout`), tops
/// aligned: one column per child view, so a side with nothing to show leaves the width to
/// the other. Make each child a `.focusSection()` so left and right move between them.
struct SportsColumns<Content: View>: View {
    var weights: [CGFloat] = [1, 1]
    var spacing: CGFloat = 36
    @ViewBuilder let content: Content

    var body: some View {
        SportsSplit(weights: weights, spacing: spacing).callAsFunction { content }
    }
}

/// The layout behind `SportsColumns`.
struct SportsSplit: Layout {
    var weights: [CGFloat] = [1, 1]
    var spacing: CGFloat = 36

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 1600
        let heights = zip(subviews, widths(width, count: subviews.count)).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            // The row's height is offered, so a column that fills it (`maxHeight: .infinity`) keeps
            // its focus section beside the taller one: left and right then always reach it.
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func widths(_ width: CGFloat, count: Int) -> [CGFloat] {
        let shares = (0..<count).map { $0 < weights.count ? weights[$0] : 1 }
        let total = max(shares.reduce(0, +), 0.001)
        let usable = max(0, width - spacing * CGFloat(max(0, count - 1)))
        return shares.map { usable * $0 / total }
    }
}

/// Table columns measured so headings and figures never truncate.
enum SportsTable {
    static let valueFont = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize,
                                                            weight: .regular)
    static let labelFont = UIFont.preferredFont(forTextStyle: .caption1)

    /// The width a column needs for its heading and values.
    static func width(label: String, values: [String], minimum: CGFloat = 56) -> CGFloat {
        let widest = values.map { measure($0, valueFont) }.max() ?? 0
        return max(minimum, ceil(max(widest, measure(label, labelFont))) + 20)
    }

    private static func measure(_ text: String, _ font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

/// A player's headshot in a circle, the team colour with initials while it loads or when
/// there is none (Expo `SportsPlayerPortrait`).
struct SportsPlayerPortrait: View {
    let name: String
    let headshot: String?
    var team: SportsTeam?
    var size: CGFloat = 56

    var body: some View {
        RemoteImage(url: url, size: CGSize(width: size, height: size), contentMode: .fill) { _ in
            Circle().fill(team?.color.flatMap(Color.init(hex:))?.opacity(0.7) ?? Color.white.opacity(0.15))
                .overlay(Text(initials).font(.system(size: size * 0.34, weight: .semibold)))
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color.white.opacity(0.08)))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var url: URL? { headshot.flatMap { $0.hasPrefix("https://") ? URL(string: $0) : nil } }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

/// A small heading over a group of panels ("Matchup Preview").
struct SportsSectionHeading: View {
    let title: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if let note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
