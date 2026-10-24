import Foundation

// A game's tracking data (Go `models.SportsBasketballShot`, `SportsHockeyShot`,
// `SportsWinProbabilityPoint` and `SportsScoreHistory`, Expo `sports-model.ts`), the live basketball
// and hockey situations of Expo's `SportsSituation` (`detail.sport` kinds `nba` and `nhl`), and the
// scoreboard's per-league freshness. Decoded leniently: a missing, `null` or malformed field is
// empty and a bad list item is skipped, never the page.

/// A field-goal attempt on the shot chart: feet across the court (`x`, 0 to 50) and from the
/// attacking rim (`y`), whether it went in and for how many points, and who took it.
struct SportsBasketballShot: Equatable, Identifiable {
    let id: String
    let teamId: String
    let x: Double
    let y: Double
    var made = false
    var points = 0
    var period = 0
    var periodLabel = ""
    var clock = ""
    var description = ""
    var athleteId: String?
    var playerName: String?
    var headshotUrl: String?
    var jersey: String?
}

extension SportsBasketballShot: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, teamId, x, y, made, points, period, periodLabel, clock, description, athleteId, playerName, headshotUrl, jersey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        teamId = try c.decode(String.self, forKey: .teamId)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        made = c.sportsValue(Bool.self, .made) ?? false
        points = c.sportsValue(Int.self, .points) ?? 0
        period = c.sportsValue(Int.self, .period) ?? 0
        periodLabel = c.sportsValue(String.self, .periodLabel) ?? ""
        clock = c.sportsValue(String.self, .clock) ?? ""
        description = c.sportsValue(String.self, .description) ?? ""
        let text = { (key: CodingKeys) in c.sportsText(key).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } }
        athleteId = text(.athleteId)
        playerName = text(.playerName)
        headshotUrl = text(.headshotUrl)
        jersey = text(.jersey)
    }
}

/// An NHL shot attempt in the provider's rink coordinates (feet, centre ice at 0,0; the teams
/// change ends each period): `kind` is "shot" (saved), "missed", "blocked" or "goal".
struct SportsHockeyShot: Equatable, Identifiable {
    let id: String
    let teamId: String
    let x: Double
    let y: Double
    var kind = ""
    var period = ""
    var clock = ""
    var description = ""

    var isGoal: Bool { kind == "goal" }
}

extension SportsHockeyShot: Decodable {
    private enum CodingKeys: String, CodingKey { case id, teamId, x, y, kind, period, clock, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        teamId = c.sportsValue(String.self, .teamId) ?? ""
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        kind = c.sportsValue(String.self, .kind)?.lowercased() ?? ""
        period = c.sportsValue(String.self, .period) ?? ""
        clock = c.sportsValue(String.self, .clock) ?? ""
        description = c.sportsValue(String.self, .description) ?? ""
    }
}

/// ESPN's home win probability (0 to 1) after a play, at the period and game clock it happened.
struct SportsWinProbabilityPoint: Equatable {
    var playId = ""
    let period: Int
    var periodLabel = ""
    let clock: String
    let home: Double
}

extension SportsWinProbabilityPoint: Decodable {
    private enum CodingKeys: String, CodingKey { case playId, period, periodLabel, clock, home }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decode(Int.self, forKey: .period)
        clock = try c.decode(String.self, forKey: .clock)
        home = try c.decode(Double.self, forKey: .home)
        playId = c.sportsText(.playId) ?? ""
        periodLabel = c.sportsValue(String.self, .periodLabel) ?? ""
    }
}

/// Every reported score of a basketball game in order, sent once the server has a complete,
/// validated history (the lead chart's data).
struct SportsScoreHistory: Equatable {
    var eventId = ""
    var awayTeamId = ""
    var homeTeamId = ""
    var complete = false
    var points: [SportsScorePoint] = []
}

extension SportsScoreHistory: Decodable {
    private enum CodingKeys: String, CodingKey { case eventId, awayTeamId, homeTeamId, complete, points }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = c.sportsText(.eventId) ?? ""
        awayTeamId = c.sportsText(.awayTeamId) ?? ""
        homeTeamId = c.sportsText(.homeTeamId) ?? ""
        complete = c.sportsValue(Bool.self, .complete) ?? false
        points = c.sportsList(SportsScorePoint.self, .points)
    }
}

/// The score at one moment of the history.
struct SportsScorePoint: Equatable {
    var id = ""
    let period: Int
    var periodLabel = ""
    let clock: String
    let away: Double
    let home: Double
}

extension SportsScorePoint: Decodable {
    private enum CodingKeys: String, CodingKey { case id, period, periodLabel, clock, away, home }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        period = try c.decode(Int.self, forKey: .period)
        clock = try c.decode(String.self, forKey: .clock)
        away = try c.decode(Double.self, forKey: .away)
        home = try c.decode(Double.self, forKey: .home)
        id = c.sportsText(.id) ?? ""
        periodLabel = c.sportsValue(String.self, .periodLabel) ?? ""
    }
}

/// Basketball's live situation (Expo `SportsSituation` kind `nba`): who has the ball (an id,
/// abbreviation or name) and the bonus ("PHI in the bonus"). Only a `detail.sport` of that kind.
struct SportsBasketballSituation: Equatable {
    var possession = ""
    var bonus: String?
}

extension SportsBasketballSituation: Decodable {
    private enum CodingKeys: String, CodingKey { case kind, possession, bonus }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.sportsValue(String.self, .kind) == "nba" else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "not a basketball situation")
        }
        possession = c.sportsValue(String.self, .possession)?.trimmingCharacters(in: .whitespaces) ?? ""
        bonus = c.sportsValue(String.self, .bonus).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }
}

/// Hockey's live situation (Expo `SportsSituation` kind `nhl`): the strength ("Even strength",
/// "Boston Bruins power play · 1:18") and each side's shots.
struct SportsHockeySituation: Equatable {
    var strength = ""
    var shotsAway: Int?
    var shotsHome: Int?
}

extension SportsHockeySituation: Decodable {
    private enum CodingKeys: String, CodingKey { case kind, strength, shotsAway, shotsHome }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.sportsValue(String.self, .kind) == "nhl" else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "not a hockey situation")
        }
        strength = c.sportsValue(String.self, .strength)?.trimmingCharacters(in: .whitespaces) ?? ""
        shotsAway = c.sportsValue(Int.self, .shotsAway).flatMap { $0 >= 0 ? $0 : nil }
        shotsHome = c.sportsValue(Int.self, .shotsHome).flatMap { $0 >= 0 ? $0 : nil }
    }
}

extension SportsGame {
    /// Basketball's situation while live (any basketball league).
    var liveBasketballSituation: SportsBasketballSituation? {
        lifecycle == .live && SportsKind.kind(leagueID: league) == .basketball ? detail?.basketballSituation : nil
    }

    /// The NHL's situation while live.
    var liveHockeySituation: SportsHockeySituation? {
        lifecycle == .live && league == "nhl" ? detail?.hockeySituation : nil
    }

    /// The side a situation names by id, abbreviation or name, in any case.
    func side(named key: String) -> SportsTeam? {
        let key = key.lowercased()
        guard !key.isEmpty else { return nil }
        return [awayTeam, homeTeam].first { team in
            [team.id, team.abbreviation ?? "", team.name].contains { $0.lowercased() == key }
        }
    }
}

/// A league's freshness on the scoreboard (Go `BackendLeagueAvailability`): stale when the
/// server kept serving its last good answer, unavailable when it has none.
struct SportsLeagueFreshness: Equatable, Decodable {
    let league: String
    var updatedAt: String?
    var stale = false
    var unavailable = false

    private enum CodingKeys: String, CodingKey { case league, updatedAt, stale, unavailable }

    init(league: String, stale: Bool = false, unavailable: Bool = false) {
        self.league = league
        self.stale = stale
        self.unavailable = unavailable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        league = try c.decode(String.self, forKey: .league)
        updatedAt = c.sportsValue(String.self, .updatedAt)
        stale = c.sportsValue(Bool.self, .stale) ?? false
        unavailable = c.sportsValue(Bool.self, .unavailable) ?? false
    }
}
