import Foundation

// The individual and other sports' data (Go `models.SportsGolfEntry`, `SportsCricketInnings`,
// `SportsCricketScorecard`, the fight card of `SportsCombat`, Expo `sports-model.ts`): golf's
// leaderboard, cricket's innings and player scorecards, a fight card's bouts, and a game's listed
// participants (golf's field on the scoreboard). Decoded leniently: a missing, `null` or malformed
// field is empty and a bad list item is skipped, never the page.

/// A golfer on the leaderboard: the tournament score to par and each round's strokes and holes.
struct SportsGolfEntry: Equatable, Decodable, Identifiable {
    let id: String
    let name: String
    var score: String?
    var rounds: [SportsGolfRound] = []

    private enum CodingKeys: String, CodingKey { case id, name, score, rounds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        score = c.sportsText(.score).flatMap { $0.isEmpty ? nil : $0 }
        rounds = c.sportsList(SportsGolfRound.self, .rounds)
    }

    /// The latest round played ("R4"), for the hub card.
    var latestRound: Int? { rounds.map(\.round).max() }
}

/// One round: strokes, score to par and the holes played.
struct SportsGolfRound: Equatable, Decodable {
    let round: Int
    var strokes: String?
    var toPar: String?
    var holes: [SportsGolfHole] = []

    private enum CodingKeys: String, CodingKey { case round, strokes, toPar, holes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        round = try c.decode(Int.self, forKey: .round)
        strokes = c.sportsText(.strokes).flatMap { $0.isEmpty ? nil : $0 }
        toPar = c.sportsText(.toPar).flatMap { $0.isEmpty ? nil : $0 }
        holes = c.sportsList(SportsGolfHole.self, .holes)
    }
}

struct SportsGolfHole: Equatable, Decodable {
    let hole: Int
    let strokes: String
    var toPar: String?

    private enum CodingKeys: String, CodingKey { case hole, strokes, toPar }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hole = try c.decode(Int.self, forKey: .hole)
        strokes = c.sportsText(.strokes) ?? ""
        toPar = c.sportsText(.toPar).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A cricket innings: the side batting, its order in the match, runs, wickets, overs, the
/// target being chased, and whether the feed says it is the one in progress (`batting`).
struct SportsCricketInnings: Equatable, Decodable {
    let teamId: String
    let number: Int
    var score: String?
    var target: Int?
    var batting: Bool?
    var runs: Int?
    var wickets: Int?
    var overs: String?
    var description: String?

    private enum CodingKeys: String, CodingKey { case teamId, number, score, target, batting, runs, wickets, overs, description }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teamId = try c.decode(String.self, forKey: .teamId)
        number = try c.decode(Int.self, forKey: .number)
        score = c.sportsValue(String.self, .score).flatMap { $0.isEmpty ? nil : $0 }
        target = c.sportsValue(Int.self, .target)
        batting = c.sportsValue(Bool.self, .batting)
        runs = c.sportsValue(Int.self, .runs)
        wickets = c.sportsValue(Int.self, .wickets)
        overs = c.sportsText(.overs).flatMap { $0.isEmpty ? nil : $0 }
        description = c.sportsValue(String.self, .description).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// One side's batting or bowling card for an innings.
struct SportsCricketScorecard: Equatable, Decodable {
    enum Kind: String, Decodable { case batting, bowling }

    let kind: Kind
    let innings: Int
    var teamId: String?
    let teamName: String
    var extras: String?
    var players: [SportsCricketPlayer] = []

    private enum CodingKeys: String, CodingKey { case kind, innings, teamId, teamName, extras, players }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        innings = try c.decode(Int.self, forKey: .innings)
        teamId = c.sportsValue(String.self, .teamId)
        teamName = c.sportsValue(String.self, .teamName) ?? ""
        extras = c.sportsValue(String.self, .extras).flatMap { $0.isEmpty ? nil : $0 }
        players = c.sportsList(SportsCricketPlayer.self, .players)
    }
}

struct SportsCricketPlayer: Equatable, Decodable, Identifiable {
    let id: String
    let name: String
    var headshotUrl: String?
    var dismissal: String?
    var stats: [SportsStat] = []

    private enum CodingKeys: String, CodingKey { case id, name, headshotUrl, dismissal, stats }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        headshotUrl = c.sportsValue(String.self, .headshotUrl)
        dismissal = c.sportsValue(String.self, .dismissal).flatMap { $0.isEmpty ? nil : $0 }
        stats = c.sportsList(SportsStat.self, .stats)
    }

    func value(_ label: String) -> String? { stats.first { $0.label == label }?.value }
}

/// A fight card (or a bout of one): its name, the bout's division and scheduled rounds, and every
/// bout on the card in the feed's order.
struct SportsCombat: Decodable, Hashable {
    var cardName: String?
    var division: String?
    var scheduledRounds: Int?
    var bouts: [SportsCombatBout] = []

    private enum CodingKeys: String, CodingKey { case cardName, division, scheduledRounds, bouts }

    init(cardName: String? = nil, division: String? = nil, scheduledRounds: Int? = nil, bouts: [SportsCombatBout] = []) {
        self.cardName = cardName
        self.division = division
        self.scheduledRounds = scheduledRounds
        self.bouts = bouts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardName = c.sportsValue(String.self, .cardName).flatMap { $0.isEmpty ? nil : $0 }
        division = c.sportsValue(String.self, .division).flatMap { $0.isEmpty ? nil : $0 }
        scheduledRounds = c.sportsValue(Int.self, .scheduledRounds)
        bouts = c.sportsList(SportsCombatBout.self, .bouts)
    }
}

/// A bout on a card: both fighters, the division, its state and when it ended.
struct SportsCombatBout: Decodable, Hashable, Identifiable {
    let id: String
    let away: SportsTeam
    let home: SportsTeam
    var division: String?
    var status = "scheduled"
    var period: String?
    var clock: String?

    private enum CodingKeys: String, CodingKey { case id, away, home, division, status, period, clock }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        away = try c.decode(SportsTeam.self, forKey: .away)
        home = try c.decode(SportsTeam.self, forKey: .home)
        division = c.sportsValue(String.self, .division).flatMap { $0.isEmpty ? nil : $0 }
        status = c.sportsValue(String.self, .status) ?? "scheduled"
        period = c.sportsValue(String.self, .period).flatMap { $0.isEmpty ? nil : $0 }
        clock = c.sportsValue(String.self, .clock).flatMap { $0.isEmpty ? nil : $0 }
    }

    var lifecycle: SportsLifecycle { SportsLifecycle(status: status, detail: nil) }
}

/// A player, fighter or team the scoreboard lists for an event, in its order (golf's field with
/// each golfer's score to par).
struct SportsParticipant: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    var abbreviation: String?
    var score: String?
    var position: Int?
    var winner: Bool?

    private enum CodingKeys: String, CodingKey { case id, name, abbreviation, score, position, winner }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.sportsText(.id) ?? ""
        name = c.sportsValue(String.self, .name) ?? ""
        abbreviation = c.sportsValue(String.self, .abbreviation)
        score = c.sportsText(.score).flatMap { $0.isEmpty ? nil : $0 }
        position = c.sportsValue(Int.self, .position)
        winner = c.sportsValue(Bool.self, .winner)
    }
}

/// The scoreboard's participants as a list where a malformed one is skipped (a bad item never
/// costs the game).
struct SportsParticipants: Decodable, Hashable {
    var items: [SportsParticipant] = []

    init(_ items: [SportsParticipant] = []) { self.items = items }

    init(from decoder: Decoder) throws {
        items = try LossyArray<SportsParticipant>(from: decoder).elements.filter { !$0.name.isEmpty }
    }
}
