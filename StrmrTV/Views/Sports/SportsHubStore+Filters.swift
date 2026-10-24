import Foundation

/// The hub's rows and filters: Following, the Sport and League choices (pinned sports and followed
/// competitions first), follow order within each row, and Competition Details (Expo `SportsHubTV`'s
/// filters and `prioritizeSportsHub`).
extension SportsHubStore {
    /// A league's sport family: the catalog's, else the feed's sport on one of its games.
    func family(_ league: String) -> String? {
        if let entry = leagues[league] { return SportsHubFilters.family(entry) }
        return SportsHubFilters.family(sport: games.first { $0.league == league }?.sport)
    }

    private func followID(_ league: String) -> String {
        leagues[league]?.followID ?? SportsLeague.followAliases[league] ?? league
    }

    /// A followed competition or team, or the event's sport pinned (Expo's Following filter).
    func isFollowed(_ item: SportsHubItem) -> Bool {
        switch item {
        case let .game(game): isFollowed(game)
        case let .race(listing): SportsRaceHub.isFollowed(listing.session.league, competitions: followed, pinned: pinned)
        case let .cycling(listing): SportsCycling.isFollowed(listing.race, competitions: followed, pinned: pinned)
        }
    }

    func isFollowed(_ game: SportsGame) -> Bool {
        if followed.contains(followID(game.league)) { return true }
        if let family = family(game.league), pinned.contains(family) { return true }
        let teams = preferences?.preferences.teamIds ?? []
        return teams.contains("\(game.league):\(game.homeTeam.id)") || teams.contains("\(game.league):\(game.awayTeam.id)")
    }

    /// Followed competitions first, in follow order; then pinned sports in pin order (Expo
    /// `priority`); then a game with a followed team.
    func rank(_ item: SportsHubItem) -> Int {
        switch item {
        case let .game(game):
            if let follow = followed.firstIndex(of: followID(game.league)) { return follow }
            if let family = family(game.league), let pin = pinned.firstIndex(of: family) { return followed.count + pin }
            return isFollowed(game) ? followed.count + pinned.count : Int.max
        case let .race(listing):
            return SportsRaceHub.followRank(listing.session.league, competitions: followed, pinned: pinned)
        case let .cycling(listing):
            return SportsCycling.followRank(listing.race, competitions: followed, pinned: pinned)
        }
    }

    /// What the Sport and League filters see of a card.
    func subject(_ item: SportsHubItem) -> SportsFilterSubject {
        switch item {
        case let .game(game): SportsFilterSubject(sport: family(game.league), league: game.league, college: leagues[game.league]?.college == true)
        case let .race(listing): SportsFilterSubject(sport: SportsHubFilters.motorsport, league: listing.session.league)
        case let .cycling(listing): SportsFilterSubject(sport: SportsCycling.sport, league: listing.race.followID)
        }
    }

    /// The Sport filter's choices: the sports with a league turned on, pinned first.
    var sportOptions: [SportsFilterOption] { SportsHubFilters.sportOptions(catalog, pinned: pinned) }

    /// The League filter's choices for the chosen sport.
    var leagueOptions: [SportsFilterOption] {
        SportsHubFilters.leagueOptions(sport, catalog: catalog, cyclingRaces: cyclingFeed?.races ?? [], followed: followed, pinned: pinned)
    }

    /// "All Leagues", or the chosen league's name.
    var leagueLabel: String {
        if league == SportsHubFilters.all { return String(localized: "All Leagues") }
        return leagueOptions.first { $0.id == league }?.label ?? leagueName(league)
    }

    /// A sport or league is chosen.
    var filtered: Bool { sport != SportsHubFilters.all || league != SportsHubFilters.all }

    /// Whether the hub offers Competition Details for the chosen sport or league.
    var hasDetails: Bool { SportsHubFilters.hasDetails(sport: sport, league: league, catalog: leagues) }

    /// Live Now, Upcoming, Results and Schedule Updates; followed competitions and pinned sports
    /// first in each.
    var sections: [SportsSection] {
        let items = games.map { SportsHubItem.game(withRecord($0)) } + raceItems + cyclingItems
        // A chosen sport no longer offered counts as All.
        let sport = sport == SportsHubFilters.all || sportOptions.contains { $0.id == sport } ? sport : SportsHubFilters.all
        var pool = items.filter { SportsHubFilters.matches(subject($0), sport: sport, league: league) }
        if followingOnly { pool = pool.filter(isFollowed) }
        let all = [SportsSection.Kind.live, .upcoming, .results, .changes].map { kind in
            SportsSection(kind: kind, items: ordering.ordered(pool.filter { kind.contains($0.lifecycle) }, in: kind, rank: rank))
        }
        let kinds: Set<SportsSection.Kind> = switch filter {
        case .all: [.live, .upcoming, .results, .changes]
        case .live: [.live]
        case .upcoming: [.upcoming, .changes]
        case .results: [.results]
        }
        return all.filter { kinds.contains($0.kind) && !$0.items.isEmpty }
    }
}
