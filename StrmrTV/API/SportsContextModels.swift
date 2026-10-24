import Foundation

// The context a game's detail carries beside its stats: the pre-game preview, the league
// table snapshot, match lineups and American football drives (Go `models/sports_pregame.go`
// and `models/sports_detail.go`, Expo `sports-model.ts`). Lists decode leniently.

/// Season context for a game (`detail.pregame`, Expo `SportsPregame`): each side's record,
/// standing, recent results, season leaders and probable starters, season comparisons, and
/// the previous meeting. Shown before the start; with scores hidden only what was known
/// before the start shows (`spoilerSafe`).
struct SportsPregame: Equatable {
    var seasonLabel: String?
    var updatedAt: String?
    var teams: [SportsPregameTeam] = []
    var comparisons: [SportsComparison] = []
    var previousMeeting: SportsPreviousMeeting?

    func team(_ id: String) -> SportsPregameTeam? { teams.first { $0.teamId == id } }
}

extension SportsPregame: Decodable {
    private enum CodingKeys: String, CodingKey { case seasonLabel, updatedAt, teams, comparisons, previousMeeting }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seasonLabel = c.sportsValue(String.self, .seasonLabel).flatMap { $0.isEmpty ? nil : $0 }
        updatedAt = c.sportsValue(String.self, .updatedAt)
        teams = c.sportsList(SportsPregameTeam.self, .teams)
        comparisons = c.sportsList(SportsComparison.self, .comparisons)
        previousMeeting = c.sportsValue(SportsPreviousMeeting.self, .previousMeeting)
    }
}

/// One side's season context.
struct SportsPregameTeam: Equatable {
    var teamId: String
    var record: String?
    var homeRecord: String?
    var awayRecord: String?
    var conferenceRecord: String?
    var rank: Int?
    /// The table it stands in ("2026-27 Central Standings").
    var standingLabel: String?
    var standingStats: [SportsStat] = []
    /// Latest completed games first.
    var recent: [SportsRecentResult] = []
    var leaders: [SportsPregamePlayer] = []
    var probables: [SportsPregamePlayer] = []
}

extension SportsPregameTeam: Decodable {
    private enum CodingKeys: String, CodingKey {
        case teamId, record, homeRecord, awayRecord, conferenceRecord, rank, standingLabel, standingStats, recent, leaders, probables
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamId = try c.decode(String.self, forKey: .teamId)
        record = c.sportsValue(String.self, .record)
        homeRecord = c.sportsValue(String.self, .homeRecord)
        awayRecord = c.sportsValue(String.self, .awayRecord)
        conferenceRecord = c.sportsValue(String.self, .conferenceRecord)
        rank = c.sportsValue(Int.self, .rank)
        standingLabel = c.sportsValue(String.self, .standingLabel)
        standingStats = c.sportsList(SportsStat.self, .standingStats)
        recent = c.sportsList(SportsRecentResult.self, .recent)
        leaders = c.sportsList(SportsPregamePlayer.self, .leaders)
        probables = c.sportsList(SportsPregamePlayer.self, .probables)
    }
}

/// A completed game in a side's recent form ("W", "Toronto Raptors", "135-92").
struct SportsRecentResult: Equatable, Decodable, Identifiable {
    let id: String
    /// RFC 3339.
    let date: String
    let opponent: String
    let result: String
    let score: String?
}

/// A season leader ("Points", "Norman Powell", "15.0") or probable starter.
struct SportsPregamePlayer: Equatable, Decodable {
    let name: String
    let label: String
    let value: String?
}

struct SportsPreviousMeeting: Equatable, Decodable {
    let date: String
    let homeTeamId: String
    let awayTeamId: String
    let homeScore: String
    let awayScore: String

    private enum CodingKeys: String, CodingKey { case date, homeTeamId, awayTeamId, homeScore, awayScore }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        homeTeamId = try c.decode(String.self, forKey: .homeTeamId)
        awayTeamId = try c.decode(String.self, forKey: .awayTeamId)
        homeScore = c.sportsText(.homeScore) ?? ""
        awayScore = c.sportsText(.awayScore) ?? ""
    }
}

/// A league table snapshot sent with the game (`detail.standings`, Expo `SportsStandingGroup`):
/// soccer tables carry played / goal difference / points, others records.
struct SportsStandingGroup: Equatable {
    var title: String
    var rows: [SportsStandingRow] = []
}

extension SportsStandingGroup: Decodable {
    private enum CodingKeys: String, CodingKey { case title, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.sportsValue(String.self, .title) ?? ""
        rows = c.sportsList(SportsStandingRow.self, .rows)
    }
}

struct SportsStandingRow: Equatable {
    var teamId: String
    var name: String
    var rank: String?
    var played: String?
    var points: String?
    var goalDifference: String?
    var record: String?
    var conferenceRecord: String?
}

extension SportsStandingRow: Decodable {
    private enum CodingKeys: String, CodingKey { case teamId, name, rank, played, points, goalDifference, record, conferenceRecord }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamId = c.sportsText(.teamId) ?? ""
        name = try c.decode(String.self, forKey: .name)
        rank = c.sportsText(.rank)
        played = c.sportsText(.played)
        points = c.sportsText(.points)
        goalDifference = c.sportsText(.goalDifference)
        record = c.sportsValue(String.self, .record)
        conferenceRecord = c.sportsValue(String.self, .conferenceRecord)
    }
}

/// A side's match squad (`detail.lineups`, Expo `SportsLineup`): starters, substitutes and
/// who came on or went off.
struct SportsLineup: Equatable {
    var teamId: String
    var formation: String?
    var players: [SportsLineupPlayer] = []
}

extension SportsLineup: Decodable {
    private enum CodingKeys: String, CodingKey { case teamId, formation, players }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamId = try c.decode(String.self, forKey: .teamId)
        formation = c.sportsValue(String.self, .formation).flatMap { $0.isEmpty ? nil : $0 }
        players = c.sportsList(SportsLineupPlayer.self, .players)
    }
}

struct SportsLineupPlayer: Equatable, Identifiable {
    var id: String
    var name: String
    var number: String?
    var position: String?
    var starter = false
    var subbedIn = false
    var subbedOut = false
}

extension SportsLineupPlayer: Decodable {
    private enum CodingKeys: String, CodingKey { case id, name, number, position, starter, subbedIn, subbedOut }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        number = c.sportsText(.number)
        position = c.sportsValue(String.self, .position).flatMap { $0.isEmpty ? nil : $0 }
        starter = c.sportsValue(Bool.self, .starter) ?? false
        subbedIn = c.sportsValue(Bool.self, .subbedIn) ?? false
        subbedOut = c.sportsValue(Bool.self, .subbedOut) ?? false
    }
}

/// An American football drive (`detail.footballDrives`, NFL and college only). Field
/// positions run 0 (away end zone) to 100 (home end zone).
struct SportsFootballDrive: Equatable, Identifiable {
    var id: String
    var teamId: String
    var period = ""
    /// "TD", "FG", "PUNT", "DOWNS"…
    var result = ""
    var startLabel = ""
    var endLabel = ""
    /// "6 plays, 23 yards, 3:30".
    var description = ""
    var current = false
    var start: Double?
    var end: Double?
    /// False when the feed says it couldn't place the start or the end.
    var startKnown: Bool?
    var endKnown: Bool?
    var playCount: Int?
    var yards: Double?
    var elapsed: String?
    var plays: [SportsFootballPlay] = []
}

extension SportsFootballDrive: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, teamId, period, result, startLabel, endLabel, description, current, start, end, playCount, yards, elapsed, plays
        case startKnown, endKnown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        teamId = c.sportsText(.teamId) ?? ""
        period = c.sportsValue(String.self, .period) ?? ""
        result = c.sportsValue(String.self, .result) ?? ""
        startLabel = c.sportsValue(String.self, .startLabel) ?? ""
        endLabel = c.sportsValue(String.self, .endLabel) ?? ""
        description = c.sportsValue(String.self, .description) ?? ""
        current = c.sportsValue(Bool.self, .current) ?? false
        start = c.sportsValue(Double.self, .start)
        end = c.sportsValue(Double.self, .end)
        startKnown = c.sportsValue(Bool.self, .startKnown)
        endKnown = c.sportsValue(Bool.self, .endKnown)
        playCount = c.sportsValue(Int.self, .playCount)
        yards = c.sportsValue(Double.self, .yards)
        elapsed = c.sportsValue(String.self, .elapsed).flatMap { $0.isEmpty ? nil : $0 }
        plays = c.sportsList(SportsFootballPlay.self, .plays)
    }
}

/// A play of a drive, with down, distance and field positions.
struct SportsFootballPlay: Equatable, Decodable, Identifiable {
    let id: String
    let type: String
    let description: String
    let clock: String?
    let period: String?
    let typeId: String?
    let wallclock: String?
    let down: Int?
    let distance: Double?
    let yards: Double?
    let possessionTeamId: String?
    let start: Double?
    let end: Double?
    let scoring: Bool?
}
