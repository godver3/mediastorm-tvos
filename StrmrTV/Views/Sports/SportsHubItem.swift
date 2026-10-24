import Foundation

/// Something the hub's rows can order: a stable id and when it starts.
protocol SportsHubEntry {
    var id: String { get }
    var start: Date { get }
}

extension SportsGame: SportsHubEntry {}

/// One card of the Sports hub (Expo `HubCard`): a game, a race weekend's session, or a cycling
/// race's stage (or rest day). Rows sort them together by lifecycle and start.
enum SportsHubItem: Identifiable, Hashable, SportsHubEntry {
    case game(SportsGame)
    case race(SportsRaceListing)
    case cycling(SportsCyclingListing)

    /// Unique across kinds: the row's item key.
    var id: String {
        switch self {
        case let .game(game): game.id
        case let .race(listing): listing.key
        case let .cycling(listing): listing.key
        }
    }

    var league: String {
        switch self {
        case let .game(game): game.league
        case let .race(listing): listing.session.league
        case let .cycling(listing): listing.race.followID
        }
    }

    var lifecycle: SportsLifecycle {
        switch self {
        case let .game(game): game.lifecycle
        case let .race(listing): listing.lifecycle
        case let .cycling(listing): listing.lifecycle
        }
    }

    var start: Date {
        switch self {
        case let .game(game): game.start
        case let .race(listing): listing.session.start ?? .distantPast
        case let .cycling(listing): listing.start
        }
    }
}
