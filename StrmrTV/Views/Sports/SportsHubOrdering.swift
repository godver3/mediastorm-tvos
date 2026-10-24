import Foundation

/// The hub's order within each row (Expo `SportsHubShowcase`'s stable identity order): a game takes
/// a place the first time a load lists it, by start and then id, and keeps it, so score and clock
/// updates, and games that start together, never swap cards between refreshes. Upcoming games
/// follow their start (a delay moves one, as in Expo), with the place breaking ties; results show
/// the latest first. Followed competitions lead every row (`rank`). Games and race sessions
/// (`SportsHubItem`) share the rows.
struct SportsHubOrdering {
    private var places: [String: Int] = [:]

    /// Gives each game not seen before the next place, in start-then-id order.
    mutating func record<Entry: SportsHubEntry>(_ games: [Entry]) {
        for game in games.sorted(by: { Self.byStart($0, $1) }) where places[game.id] == nil {
            places[game.id] = places.count
        }
    }

    /// Forgets every place (another day).
    mutating func reset() { places = [:] }

    func place(_ game: some SportsHubEntry) -> Int { places[game.id] ?? Int.max }

    /// A row's games in the order the hub shows them.
    func ordered<Entry: SportsHubEntry>(_ games: [Entry], in kind: SportsSection.Kind, rank: (Entry) -> Int) -> [Entry] {
        games.sorted { a, b in
            let first = rank(a), second = rank(b)
            if first != second { return first < second }
            switch kind {
            case .upcoming:
                return a.start != b.start ? a.start < b.start : place(a) < place(b)
            case .results:
                return place(a) > place(b)
            case .live, .changes:
                return place(a) < place(b)
            }
        }
    }

    /// By start, then id: one order for games that start together, whatever order the feed sends.
    static func byStart<Entry: SportsHubEntry>(_ a: Entry, _ b: Entry) -> Bool {
        a.start != b.start ? a.start < b.start : a.id < b.id
    }
}

extension SportsSection.Kind {
    /// Whether a game belongs in this row.
    func contains(_ game: SportsGame) -> Bool { contains(game.lifecycle) }

    /// Whether a card in this lifecycle belongs in this row.
    func contains(_ lifecycle: SportsLifecycle) -> Bool {
        switch self {
        case .live: lifecycle == .live
        case .upcoming: lifecycle == .scheduled
        case .results: lifecycle == .final
        case .changes: lifecycle.isScheduleChange
        }
    }
}
