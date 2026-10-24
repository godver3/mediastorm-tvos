import Foundation

/// A game page's data: `detail` of `GET /api/sports/game/{id}` (Go `models.SportsGameDetail`,
/// Expo `SportsEventDetail`). Decoded leniently: a missing, `null` or malformed field is
/// empty and a bad list item is skipped, so one odd value never costs the page. The
/// tracking data's types are in `SportsTrackingModels.swift`, golf's, cricket's and combat's in
/// `SportsIndividualModels.swift`.
struct SportsGameDetail: Equatable {
    var source: String?
    /// When the server built this detail (RFC 3339), for the page's freshness.
    var updatedAt: String?
    var stale = false
    var coverageNote: String?
    /// The soccer feed's competition and round ("2025-26 English Premier League").
    var tournamentContext: String?
    var capabilities = SportsCapabilities()
    var periods: [SportsPeriodScore] = []
    /// Newest first, as the feed sends them.
    var plays: [SportsPlay] = []
    var comparisons: [SportsComparison] = []
    var leaders: [SportsLeader] = []
    var playerStats: [SportsPlayerStats] = []
    var pregame: SportsPregame?
    var standings: [SportsStandingGroup] = []
    var lineups: [SportsLineup] = []
    var footballDrives: [SportsFootballDrive] = []
    /// MLB's at-bat with the players' box-score ids (Go `detail.sport`).
    var sport: SportsBaseballSituation?
    /// Basketball's field-goal attempts in game order (the shot chart).
    var basketballShots: [SportsBasketballShot] = []
    /// ESPN's home win probability after each play (basketball).
    var winProbability: [SportsWinProbabilityPoint] = []
    /// Every reported score, once complete (basketball's lead chart).
    var scoreHistory: SportsScoreHistory?
    /// NHL shot attempts on the rink.
    var shots: [SportsHockeyShot] = []
    /// `detail.sport` of kind `nba`: possession and the bonus.
    var basketballSituation: SportsBasketballSituation?
    /// `detail.sport` of kind `nhl`: the strength and each side's shots.
    var hockeySituation: SportsHockeySituation?
    /// Golf's leaderboard, in the feed's order.
    var leaderboard: [SportsGolfEntry] = []
    /// Cricket's innings and player scorecards.
    var innings: [SportsCricketInnings] = []
    var cricketScorecards: [SportsCricketScorecard] = []
    /// A bout's fighters: height, reach, weight, stance (one `SportsPlayerStats` each).
    var fighterProfiles: [SportsPlayerStats] = []
}

extension SportsGameDetail: Decodable {
    private enum CodingKeys: String, CodingKey {
        case source, updatedAt, stale, coverageNote, tournamentContext, capabilities, periods, plays, comparisons
        case leaders, playerStats, pregame, standings, lineups, footballDrives, sport
        case basketballShots, winProbability, scoreHistory, shots, leaderboard, innings, cricketScorecards, fighterProfiles
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = c.sportsValue(String.self, .source)
        updatedAt = c.sportsValue(String.self, .updatedAt)
        stale = c.sportsValue(Bool.self, .stale) ?? false
        coverageNote = c.sportsValue(String.self, .coverageNote).flatMap { $0.isEmpty ? nil : $0 }
        tournamentContext = c.sportsValue(String.self, .tournamentContext).flatMap { $0.isEmpty ? nil : $0 }
        capabilities = c.sportsValue(SportsCapabilities.self, .capabilities) ?? SportsCapabilities()
        periods = c.sportsList(SportsPeriodScore.self, .periods)
        plays = c.sportsList(SportsPlay.self, .plays)
        comparisons = c.sportsList(SportsComparison.self, .comparisons)
        leaders = c.sportsList(SportsLeader.self, .leaders)
        playerStats = c.sportsList(SportsPlayerStats.self, .playerStats)
        pregame = c.sportsValue(SportsPregame.self, .pregame)
        standings = c.sportsList(SportsStandingGroup.self, .standings)
        lineups = c.sportsList(SportsLineup.self, .lineups)
        footballDrives = c.sportsList(SportsFootballDrive.self, .footballDrives)
        sport = c.sportsValue(SportsBaseballSituation.self, .sport)
        basketballShots = c.sportsList(SportsBasketballShot.self, .basketballShots)
        winProbability = c.sportsList(SportsWinProbabilityPoint.self, .winProbability)
        scoreHistory = c.sportsValue(SportsScoreHistory.self, .scoreHistory)
        shots = c.sportsList(SportsHockeyShot.self, .shots)
        basketballSituation = c.sportsValue(SportsBasketballSituation.self, .sport)
        hockeySituation = c.sportsValue(SportsHockeySituation.self, .sport)
        leaderboard = c.sportsList(SportsGolfEntry.self, .leaderboard)
        innings = c.sportsList(SportsCricketInnings.self, .innings)
        cricketScorecards = c.sportsList(SportsCricketScorecard.self, .cricketScorecards)
        fighterProfiles = c.sportsList(SportsPlayerStats.self, .fighterProfiles)
    }
}

/// Which tabs the feed can fill for this game (Expo `detail.capabilities`).
struct SportsCapabilities: Equatable, Decodable {
    var plays = false
    var stats = false
    var winProbability = false

    init(plays: Bool = false, stats: Bool = false, winProbability: Bool = false) {
        self.plays = plays
        self.stats = stats
        self.winProbability = winProbability
    }

    private enum CodingKeys: String, CodingKey { case plays, stats, winProbability }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plays = c.sportsValue(Bool.self, .plays) ?? false
        stats = c.sportsValue(Bool.self, .stats) ?? false
        winProbability = c.sportsValue(Bool.self, .winProbability) ?? false
    }
}

/// One period's (quarter, half, set, inning) points for each side.
struct SportsPeriodScore: Equatable, Decodable {
    let label: String
    let away: String
    let home: String
    /// Tennis tiebreak points and set winners.
    var awayTiebreak: Int?
    var homeTiebreak: Int?
    var awayWinner: Bool?
    var homeWinner: Bool?

    private enum CodingKeys: String, CodingKey { case label, away, home, awayTiebreak, homeTiebreak, awayWinner, homeWinner }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        away = c.sportsText(.away) ?? ""
        home = c.sportsText(.home) ?? ""
        awayTiebreak = c.sportsValue(Int.self, .awayTiebreak)
        homeTiebreak = c.sportsValue(Int.self, .homeTiebreak)
        awayWinner = c.sportsValue(Bool.self, .awayWinner)
        homeWinner = c.sportsValue(Bool.self, .homeWinner)
    }
}

/// A team statistic for both sides ("Total yards", "Possession").
struct SportsComparison: Equatable, Decodable {
    let label: String
    let away: String
    let home: String

    init(label: String, away: String, home: String) {
        self.label = label
        self.away = away
        self.home = home
    }

    private enum CodingKeys: String, CodingKey { case label, away, home }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        away = c.sportsText(.away) ?? ""
        home = c.sportsText(.home) ?? ""
    }
}

/// A game leader ("Passing Yards", "Caleb Williams", "CHI", "22/33, 308 YDS, 2 TD").
struct SportsLeader: Equatable, Decodable {
    let label: String
    let name: String
    let teamAbbreviation: String
    let value: String
    let athleteId: String?
    let headshotUrl: String?
}

/// A play or match event. `teamId` is the side it belongs to when the feed says.
struct SportsPlay: Equatable, Decodable, Identifiable {
    let id: String
    let periodLabel: String
    let clock: String?
    let title: String
    let description: String?
    let scoring: Bool
    let teamId: String?
    let participants: [SportsPlayParticipant]
    /// A penalty-shootout kick (soccer, hockey).
    let shootout: Bool

    init(id: String, periodLabel: String = "", clock: String? = nil, title: String, description: String? = nil,
         scoring: Bool = false, teamId: String? = nil, participants: [SportsPlayParticipant] = [], shootout: Bool = false) {
        self.id = id
        self.periodLabel = periodLabel
        self.clock = clock
        self.title = title
        self.description = description
        self.scoring = scoring
        self.teamId = teamId
        self.participants = participants
        self.shootout = shootout
    }

    private enum CodingKeys: String, CodingKey { case id, periodLabel, clock, title, description, scoring, teamId, participants, shootout }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        periodLabel = c.sportsValue(String.self, .periodLabel) ?? ""
        clock = c.sportsValue(String.self, .clock).flatMap { $0.isEmpty ? nil : $0 }
        description = c.sportsValue(String.self, .description).flatMap { $0.isEmpty ? nil : $0 }
        scoring = c.sportsValue(Bool.self, .scoring) ?? false
        teamId = c.sportsValue(String.self, .teamId).flatMap { $0.isEmpty ? nil : $0 }
        participants = c.sportsList(SportsPlayParticipant.self, .participants)
        shootout = c.sportsValue(Bool.self, .shootout) ?? false
    }
}

struct SportsPlayParticipant: Equatable, Decodable {
    let id: String
    let name: String
}

/// One player's line in one category of the box score ("Passing": C/ATT 24/31, YDS 321…).
struct SportsPlayerStats: Equatable, Decodable, Identifiable {
    let id: String
    let teamId: String
    let name: String
    let category: String
    let jersey: String?
    let headshotUrl: String?
    let stats: [SportsStat]

    private enum CodingKeys: String, CodingKey { case id, teamId, name, category, jersey, headshotUrl, stats }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        teamId = try c.decode(String.self, forKey: .teamId)
        name = try c.decode(String.self, forKey: .name)
        category = c.sportsValue(String.self, .category) ?? ""
        jersey = c.sportsValue(String.self, .jersey).flatMap { $0.isEmpty ? nil : $0 }
        headshotUrl = c.sportsValue(String.self, .headshotUrl)
        stats = c.sportsList(SportsStat.self, .stats)
    }

    func value(_ label: String) -> String? { stats.first { $0.label == label }?.value }
}

/// A labelled value: a box-score column, a standings or pregame figure.
struct SportsStat: Equatable, Decodable {
    let label: String
    let value: String

    init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    private enum CodingKeys: String, CodingKey { case label, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        value = c.sportsText(.value) ?? ""
    }
}

extension KeyedDecodingContainer {
    /// An optional field; nil when missing, `null` or of another type.
    func sportsValue<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    /// A list; empty when missing, `null` or not a list, with bad items skipped.
    func sportsList<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        (try? decodeLossyArray(T.self, forKey: key)) ?? []
    }

    /// A figure the feed may send as text or as a number ("12" or 12).
    func sportsText(_ key: Key) -> String? {
        if let text = sportsValue(String.self, key) { return text }
        if let number = sportsValue(Int.self, key) { return String(number) }
        if let number = sportsValue(Double.self, key) {
            return number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
        }
        return nil
    }
}
