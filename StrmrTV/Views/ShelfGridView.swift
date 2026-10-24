import SwiftUI

/// A whole list, opened from a Home row's explore card or service card, or a Lists
/// tile. Pushed on the tab's own stack, so the tab bar keeps its tab and the page
/// carries the list's name.
struct ListPage: View {
    let list: BrowseList

    var body: some View {
        if list == .continueWatching {
            ContinueWatchingGridView()
        } else if list == .hidden {
            HiddenTitlesView()
        } else {
            BrowseGridView(list: list)
        }
    }
}

/// Every Continue Watching title as landscape cards with progress.
struct ContinueWatchingGridView: View {
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var cards: [HomeCard]?
    @State private var loadError: String?
    @State private var gridWidth: CGFloat = 0
    @FocusState private var focused: String?
    /// A card waiting for its context menu to close before it goes (see `hide`).
    @State private var pendingHide: String?

    var body: some View {
        GridPage(title: String(localized: "Continue Watching"), gridWidth: $gridWidth) {
            if let cards, cards.isEmpty {
                GridMessage(text: String(localized: "Nothing to continue."), holdsFocus: true)
            } else if let cards {
                CardGrid(items: cards, cardWidth: LandscapeCard.width, available: gridWidth) { card, width in
                    LandscapeCard(card: card, width: width) { hide(card) }
                        .focused($focused, equals: card.id)
                }
            } else if let loadError {
                GridMessage(text: loadError)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
            }
        }
        .task { await load() }
        .onChange(of: playback.sessionsEnded) { Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .continueWatchingChanged)) { _ in
            Task { await load() }
        }
        .onChange(of: focused) { _, focus in
            if let pendingHide, focus == pendingHide { completeHide(pendingHide) }
        }
    }

    private func load() async {
        do {
            cards = try await APIClient.shared.continueWatching().map(HomeCard.init)
            loadError = nil
        } catch {
            if cards == nil { loadError = error.localizedDescription }
        }
    }

    /// As on Home: the context menu is still up when this runs and hands focus back to
    /// the card on closing, so the card goes once focus is back on it (or after a second).
    private func hide(_ card: HomeCard) {
        pendingHide = card.id
        Task {
            try? await Task.sleep(for: .seconds(1))
            if pendingHide == card.id { completeHide(card.id) }
        }
    }

    /// Focus moves to the card that takes the hidden one's place (else the one before),
    /// the card goes, then the server is told; a failure reloads so it comes back.
    private func completeHide(_ id: String) {
        pendingHide = nil
        guard let cards, let index = cards.firstIndex(where: { $0.id == id }) else { return }
        let rest = cards.filter { $0.id != id }
        if !rest.isEmpty { focused = rest[min(index, rest.count - 1)].id }
        self.cards = rest
        Task {
            do { try await APIClient.shared.hideFromContinueWatching(seriesID: id) } catch { await load() }
        }
    }
}

/// A scrolling page with a heading over a card grid; reports the grid's width. The card
/// size menu sits at the heading's trailing end.
struct GridPage<Content: View>: View {
    let title: String
    @Binding var gridWidth: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .firstTextBaseline) {
                    PageHeading(title: title)
                    Spacer(minLength: 24)
                    GridCardSizeMenu()
                }
                .focusSection()
                content
            }
            .padding(.horizontal, CardGridLayout.inset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width - CardGridLayout.inset * 2 } action: { gridWidth = $0 }
        }
    }
}

/// The text a grid page shows instead of cards. `holdsFocus` makes it focusable and takes
/// focus as it appears: for a page whose last card can go (unhide, remove, hide) and that
/// has nothing else focusable. Without it focus falls to the tab bar, where Menu leaves
/// the app instead of going back.
struct GridMessage: View {
    let text: String
    var holdsFocus = false
    @FocusState private var focused: Bool

    var body: some View {
        if holdsFocus {
            label
                .foregroundStyle(focused ? .primary : .secondary)
                .focusable()
                .focused($focused)
                .onAppear { focused = true }
        } else {
            label.foregroundStyle(.secondary)
        }
    }

    private var label: some View {
        Text(text).frame(maxWidth: .infinity).padding(.top, 100)
    }
}

struct PageHeading: View {
    let title: String
    @Environment(\.sidebarInset) private var sidebarInset

    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .accessibilityAddTraits(.isHeader)
            // Below the side menu's pill, which stays over pushed pages.
            .padding(.top, sidebarInset)
    }
}

enum CardGridLayout {
    static let inset: CGFloat = 56
    static let spacing: CGFloat = 48
}

/// Cards in as many columns as fit at `cardWidth` (times the chosen grid card size),
/// widened to use the whole row.
struct CardGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let cardWidth: CGFloat
    let available: CGFloat
    /// False for grids that aren't lists (Live's channels): they keep `cardWidth`.
    var resizable = true
    /// Called when one of the last `nearEndRows` rows of cards comes on screen.
    var onNearEnd: (() -> Void)?
    var nearEndRows = 2
    @ViewBuilder let card: (Item, CGFloat) -> Card
    @ObservedObject private var cardSize = GridCardSizeStore.shared

    private var layout: (columns: [GridItem], width: CGFloat) {
        let spacing = CardGridLayout.spacing
        let cardWidth = resizable ? (cardWidth * cardSize.size.scale).rounded() : cardWidth
        let available = max(available, cardWidth)
        let count = max(1, Int((available + spacing) / (cardWidth + spacing)))
        let width = ((available - spacing * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        return (Array(repeating: GridItem(.fixed(width), spacing: spacing, alignment: .top), count: count), width)
    }

    var body: some View {
        let layout = layout
        let nearEnd = Set(items.suffix(layout.columns.count * nearEndRows).map(\.id))
        LazyVGrid(columns: layout.columns, alignment: .leading, spacing: 70) {
            ForEach(items) { item in
                card(item, layout.width)
                    .onAppear { if nearEnd.contains(item.id) { onNearEnd?() } }
            }
        }
        // Room for the focus lift and shadow inside the scroll view (see Search).
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
}
