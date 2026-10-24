import Foundation

/// A game's sport family, which picks its page's tabs, labels and Overview: the league
/// catalog's `applicationSport` (Expo `SPORTS_COMPETITIONS[league].sport`), else the game's
/// own `sport`, else what the league id says.
enum SportsKind: String {
    case football = "american-football", basketball, baseball, softball, hockey = "ice-hockey", soccer, tennis
    case golf, cricket, mma, boxing, rugbyUnion = "rugby-union", rugbyLeague = "rugby-league", volleyball, other

    init(league: SportsLeague?, game: SportsGame) {
        if let sport = league?.applicationSport, let kind = SportsKind(rawValue: sport) {
            self = kind
        } else if let sport = game.sport, let kind = Self.feedSports[sport] ?? SportsKind(rawValue: sport) {
            self = kind
        } else {
            self = Self.kind(leagueID: game.league)
        }
    }

    /// The scoreboard's own `sport` names that differ from the catalog's.
    private static let feedSports: [String: SportsKind] = ["football": .football, "hockey": .hockey, "rugby": .rugbyUnion]

    static func kind(leagueID id: String) -> SportsKind {
        switch id {
        case "nfl", "college-football": return .football
        case "nba", "wnba", "mens-college-basketball", "womens-college-basketball": return .basketball
        case "mlb": return .baseball
        case "nhl": return .hockey
        case "atp", "wta": return .tennis
        case "pga", "lpga": return .golf
        case "ufc": return .mma
        case "boxing": return .boxing
        default: break
        }
        if id.hasPrefix("soccer-") { return .soccer }
        if id.hasPrefix("rugby-league") { return .rugbyLeague }
        if id.hasPrefix("rugby-") { return .rugbyUnion }
        if id.hasPrefix("cricket") { return .cricket }
        return .other
    }

    var isRugby: Bool { self == .rugbyUnion || self == .rugbyLeague }

    /// Sides listed away first (Expo `sportsTeamSides`): the feed's first-named player or
    /// fighter is its "away" side. Team sports show the home side first.
    var awayFirst: Bool { [.tennis, .mma, .boxing, .golf].contains(self) }

    /// Soccer and tennis play matches; the rest, games (the page's notices).
    var playsMatches: Bool { self == .soccer || self == .tennis }
}

/// Everything a game page's panels read: the game, its detail (empty when the server sent
/// none), its league and sport family. Equal only while nothing on screen would change, so
/// the panels redraw on each refresh that brings new data.
struct SportsGamePage: Equatable {
    let game: SportsGame
    let league: SportsLeague?
    let kind: SportsKind
    let detail: SportsGameDetail

    init(game: SportsGame, league: SportsLeague?) {
        self.game = game
        self.league = league
        kind = SportsKind(league: league, game: game)
        detail = game.detail ?? SportsGameDetail()
    }

    var lifecycle: SportsLifecycle { game.lifecycle }
    var leagueName: String { league?.label ?? game.league.uppercased() }
    var coverageNote: String? { detail.coverageNote ?? league?.coverageNote.flatMap { $0.isEmpty ? nil : $0 } }
    var isCollege: Bool { league?.college ?? (game.league.hasPrefix("college-") || game.league.contains("-college-")) }

    /// NFL and college football, the leagues with drives (Expo `football`).
    var isFootballLeague: Bool { game.league == "nfl" || game.league == "college-football" }

    /// A golf tournament of individual players (Expo `isIndividualGolf`).
    var isIndividualGolf: Bool {
        guard kind == .golf else { return false }
        if league?.adapter == "team-golf" || ["matchup", "game", "match"].contains(league?.eventKind ?? "") { return false }
        return league?.eventKind != nil || league?.supportsTeams != true
    }

    /// The two sides in display order (Expo `sportsOrderedTeams`).
    var teams: [SportsTeam] { kind.awayFirst ? [game.awayTeam, game.homeTeam] : [game.homeTeam, game.awayTeam] }

    func team(id: String?) -> SportsTeam? {
        guard let id else { return nil }
        return [game.awayTeam, game.homeTeam].first { $0.id == id }
    }

    func team(abbreviation: String) -> SportsTeam? {
        [game.awayTeam, game.homeTeam].first { $0.abbreviation == abbreviation }
    }

    /// The comparison value of one side.
    func value(_ row: SportsComparison, for team: SportsTeam) -> String { team.id == game.homeTeam.id ? row.home : row.away }

    /// Old or flagged data (Expo's detail freshness): the server says stale, or the detail is
    /// older than 2 minutes while live, 10 minutes otherwise.
    func isStale(now: Date = Date()) -> Bool {
        guard let detail = game.detail else { return false }
        if detail.stale { return true }
        guard let updated = detail.updatedAt.flatMap(SportsGame.date) else { return true }
        return now.timeIntervalSince(updated) > (lifecycle == .live ? 120 : 600)
    }

    /// Whether the feed sent any of the generic data (Expo `SportsMatchAvailability`'s
    /// `missing`, over the fields read so far).
    var hasGameData: Bool {
        !detail.leaders.isEmpty || !detail.plays.isEmpty || !detail.comparisons.isEmpty || !detail.periods.isEmpty
            || !detail.footballDrives.isEmpty || (lifecycle != .scheduled && detail.scoreHistory != nil) || !detail.shots.isEmpty
    }
}
