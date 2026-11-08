#if os(iOS)
import SwiftUI

/// A hub card on a phone: the TV card's contents (`SportsGameCardBody`, `SportsRaceCardBody`,
/// `SportsCyclingCardBody`) on a grouped-background tile that opens the event. A live game whose
/// score changes between refreshes lights up for two seconds (Expo `SportsCardFrame`).
struct MobileSportsHubCard: View {
    let item: SportsHubItem
    @ObservedObject var store: SportsHubStore
    let spoilers: Bool

    @State private var flashes = 0
    @State private var flashing = false

    static let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        NavigationLink(value: MobileSportsRoute(item)) {
            card
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
                .background(Self.shape.fill(Color(.secondarySystemGroupedBackground)))
                .overlay {
                    Self.shape.strokeBorder(SportsStatusPill.accent, lineWidth: 2)
                        .opacity(flashing ? 1 : 0)
                        .animation(.easeOut(duration: 0.3), value: flashing)
                        .allowsHitTesting(false)
                }
                .contentShape(Self.shape)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sports-card-\(item.id)")
        .onChange(of: scoreKey) { old, new in
            if SportsScoreChange.changed(from: old, to: new) { flashes += 1 }
        }
        .task(id: flashes) {
            guard flashes > 0 else { return }
            flashing = true
            try? await Task.sleep(for: SportsScoreChange.duration)
            guard !Task.isCancelled else { return }
            flashing = false
        }
    }

    @ViewBuilder private var card: some View {
        switch item {
        case let .game(game):
            SportsGameCardBody(game: game, leagueName: store.leagueName(game.league), kind: store.kind(game),
                               spoilers: spoilers, stale: store.staleLeagues.contains(game.league))
        case let .race(listing):
            SportsRaceCardBody(listing: listing, leagueName: store.leagueName(listing.session.league), spoilers: spoilers)
        case let .cycling(listing):
            SportsCyclingCardBody(listing: listing, spoilers: spoilers)
        }
    }

    private var scoreKey: String? {
        guard case let .game(game) = item else { return nil }
        return SportsScoreChange.key(game, spoilers: spoilers)
    }
}

/// What a hub card opens.
enum MobileSportsRoute: Hashable {
    case game(SportsGameRef)
    case race(SportsRaceRef)
    case cycling(SportsCyclingRef)

    init(_ item: SportsHubItem) {
        switch item {
        case let .game(game): self = .game(SportsGameRef(id: game.id, title: game.displayTitle))
        case let .race(listing): self = .race(SportsRaceRef(weekendID: listing.weekend.id, sessionID: listing.session.id))
        case let .cycling(listing): self = .cycling(SportsCyclingRef(raceID: listing.race.id, stageID: listing.stage?.id))
        }
    }
}

/// A sports page's vertical scroll view with its content in one column: the screen's width less a
/// 16 pt margin each side, at most 900 pt (iPad), centred. The column's width is fixed, so a
/// panel of a fixed width that outgrows it can't widen the page.
struct MobileSportsScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(width: max(0, min(geometry.size.width - 32, 900)), alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

extension View {
    /// The sports pages a hub can push, registered once on the hub.
    func mobileSportsDestinations(hub: SportsHubStore) -> some View {
        navigationDestination(for: MobileSportsRoute.self) { route in
            switch route {
            case let .game(ref): MobileSportsGameView(ref: ref, hub: hub)
            case let .race(ref): MobileSportsRaceView(ref: ref, hub: hub)
            case let .cycling(ref): MobileSportsCyclingView(ref: ref, hub: hub)
            }
        }
        .navigationDestination(for: SportsGameRef.self) { MobileSportsGameView(ref: $0, hub: hub) }
        .navigationDestination(for: SportsRaceRef.self) { MobileSportsRaceView(ref: $0, hub: hub) }
        .navigationDestination(for: SportsCyclingRef.self) { MobileSportsCyclingView(ref: $0, hub: hub) }
        .navigationDestination(for: SportsCompetitionRoute.self) { MobileSportsCompetitionView(route: $0, hub: hub) }
    }
}
#endif
