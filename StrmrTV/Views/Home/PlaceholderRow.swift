import SwiftUI

/// The place of a row still loading, its cards dimmed outlines breathing under its title,
/// or of one that failed with nothing to show. While loading, its first card takes focus,
/// so Down into Home stops on the row it is waiting for (rather than skipping to whichever
/// row came in first) and Home hands focus to the row's own card when it arrives. A failed
/// row takes no focus, so focus moves past it.
struct PlaceholderRow: View {
    let id: String
    let title: String
    let failed: Bool
    let style: ShelfStyle
    let cardHeight: CGFloat
    var focused: FocusState<HomeFocus?>.Binding

    /// The focus a loading row's placeholder card takes.
    static let focusCard = "placeholder"
    static func focus(_ shelf: String) -> HomeFocus { HomeFocus(shelf: shelf, card: focusCard) }

    @State private var pulse = false

    private var cardWidth: CGFloat { (style == .landscape ? cardHeight * 16 / 9 : cardHeight * 2 / 3).rounded() }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(failed ? 0.04 : 0.1))
            .frame(width: cardWidth, height: cardHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                Text(title).font(.headline)
                if failed {
                    Label("Couldn't load. Trying again soon.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Loading…").font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 80)
            ScrollView(.horizontal) {
                HStack(spacing: 48) {
                    ForEach(0..<12, id: \.self) { index in
                        if index == 0 && !failed {
                            Button {} label: { card }
                                .cardLift()
                                .focused(focused, equals: Self.focus(id))
                        } else {
                            card
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 80, for: .scrollContent)
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .padding(.top, ShelfRow.liftRoom(cardHeight: cardHeight))
            .opacity(failed ? 1 : (pulse ? 0.45 : 1))
        }
        .onAppear {
            guard !failed else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shelf-placeholder-\(id)")
    }
}
