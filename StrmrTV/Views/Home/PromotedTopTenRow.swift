import SwiftUI

/// Today's Top 10 promoted into the hero, as on the Expo TV home: one View Details control
/// (the hero above shows the current title), Left / Right step through the ten without moving
/// focus, and while it has focus it moves on every seven seconds. A poster strip shows where
/// in the ten it is. Long press offers the watchlist and lists, as on every card.
struct PromotedTopTenRow: View {
    /// The row's one focus identity; the title it stands for changes under it.
    static let focusID = "promoted"

    let shelf: HomeShelf
    var focused: FocusState<HomeFocus?>.Binding
    @Binding var index: Int
    let cardHeight: CGFloat

    private static let rotation: Duration = .seconds(7)

    private var cards: [HomeCard] { Array(shelf.shown) }
    private var current: HomeCard? { cards.indices.contains(index) ? cards[index] : cards.first }
    private var isFocused: Bool { focused.wrappedValue?.shelf == shelf.id }
    private var posterHeight: CGFloat { (cardHeight * 0.62).rounded() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shelf.title).font(.headline)
            HStack(alignment: .center, spacing: 48) {
                if let target = current?.target {
                    NavigationLink(value: target) {
                        Label("View Details", systemImage: "info.circle")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .focused(focused, equals: HomeFocus(shelf: shelf.id, card: Self.focusID))
                    .onMoveCommand(perform: step)
                    .contextMenu { TitleActionsMenu(target: target) }
                    .accessibilityLabel(Text("View details for \(current?.title ?? "")"))
                    .accessibilityHint(Text("Left and right change the title"))
                    .layoutPriority(1)
                }
                if let badge = current?.badge {
                    Text(badge.text)
                        .font(.system(size: 40, weight: .heavy))
                        .monospacedDigit()
                        .fixedSize()
                        .layoutPriority(1)
                        .accessibilityHidden(true)
                }
                posterStrip
            }
            .padding(.top, ShelfRow.liftRoom(cardHeight: cardHeight))
        }
        .padding(.horizontal, 80)
        .task(id: "\(isFocused)-\(index)-\(cards.count)") {
            guard isFocused, cards.count > 1 else { return }
            try? await Task.sleep(for: Self.rotation)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { index = (index + 1) % cards.count }
        }
        .onChange(of: cards.count) { _, count in if index >= count { index = 0 } }
    }

    private func step(_ direction: MoveCommandDirection) {
        let next: Int
        switch direction {
        case .left: next = max(index - 1, 0)
        case .right: next = min(index + 1, cards.count - 1)
        default: return
        }
        guard next != index else { return }
        withAnimation(.easeInOut(duration: 0.3)) { index = next }
    }

    /// The ten posters, the current one full size and lit, the rest smaller and dimmed.
    private var posterStrip: some View {
        HStack(spacing: 14) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { offset, card in
                let selected = offset == index
                RemoteImage(url: LandscapeCard.artURL(card, poster: true),
                            size: CGSize(width: (posterHeight * 2 / 3).rounded(), height: posterHeight),
                            contentMode: .fill) { _ in Color.white.opacity(0.08) }
                    .frame(width: (posterHeight * 2 / 3).rounded(), height: posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(selected && isFocused ? 0.9 : 0), lineWidth: 3)
                    }
                    .scaleEffect(selected ? 1 : 0.86, anchor: .bottom)
                    .opacity(selected ? 1 : 0.5)
            }
        }
        .accessibilityHidden(true)
    }
}
