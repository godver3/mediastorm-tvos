import Foundation

// The live situation a game carries while it is played (Go `models.SportsFootballSituation` and
// `models.SportsMLBSituation`, Expo `SportsSituation`): American football's possession, down and
// distance (`footballSituation` on NFL and college games) and baseball's at-bat (`liveSituation`
// on MLB games, `detail.sport` in the game's detail, which adds the players' ids and the pitch
// count). Decoded leniently: a missing, `null` or malformed field is empty.

/// NFL and college football's live situation (Expo `SportsSituation` kind `nfl`): who has the
/// ball ("NE", an id or a name), "3rd & 4", "CHI 12", and each side's timeouts left.
struct SportsFootballSituation: Equatable {
    var possession = ""
    var downDistance = ""
    var fieldPosition = ""
    /// Timeouts left; nil when the feed didn't say (never read as none left).
    var awayTimeouts: Int?
    var homeTimeouts: Int?
}

extension SportsFootballSituation: Decodable {
    private enum CodingKeys: String, CodingKey { case possession, downDistance, fieldPosition, awayTimeouts, homeTimeouts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        possession = c.sportsValue(String.self, .possession)?.trimmingCharacters(in: .whitespaces) ?? ""
        downDistance = c.sportsValue(String.self, .downDistance)?.trimmingCharacters(in: .whitespaces) ?? ""
        fieldPosition = c.sportsValue(String.self, .fieldPosition)?.trimmingCharacters(in: .whitespaces) ?? ""
        awayTimeouts = c.sportsValue(Int.self, .awayTimeouts)
        homeTimeouts = c.sportsValue(Int.self, .homeTimeouts)
    }
}

extension SportsFootballSituation {
    /// The side with the ball: the feed names it by id, abbreviation or name, in any case.
    func offense(in game: SportsGame) -> SportsTeam? { game.side(named: possession) }

    /// "Ball at CHI 12" (Expo's scoreboard), nil when the spot isn't reported.
    var ballAt: String? { fieldPosition.isEmpty ? nil : String(localized: "Ball at \(fieldPosition)") }

    /// A side's timeouts left, 0 to 3; nil when not reported or out of range.
    func timeouts(for team: SportsTeam, in game: SportsGame) -> Int? {
        let count = team.id == game.homeTeam.id ? homeTimeouts : awayTimeouts
        return count.flatMap { (0...3).contains($0) ? $0 : nil }
    }
}

/// MLB's live at-bat (Expo `SportsSituation` kind `mlb`): the half-inning ("Top 7th"), the count,
/// outs, the runners ("Runners on 1st & 3rd"), and who pitches to whom. The page's detail adds the
/// players' box-score ids and the pitcher's pitch count.
struct SportsBaseballSituation: Equatable {
    var inning = ""
    var balls: Int?
    var strikes: Int?
    var outs: Int?
    var bases: String?
    var pitcher: String?
    var pitcherId: String?
    var pitcherPitchCount: Int?
    var batter: String?
    var batterId: String?
}

extension SportsBaseballSituation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case inning, balls, strikes, outs, bases, pitcher, pitcherId, pitcherPitchCount, batter, batterId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = { (key: CodingKeys) in c.sportsText(key).flatMap { $0.isEmpty ? nil : $0 } }
        inning = c.sportsValue(String.self, .inning) ?? ""
        balls = c.sportsValue(Int.self, .balls)
        strikes = c.sportsValue(Int.self, .strikes)
        outs = c.sportsValue(Int.self, .outs)
        bases = text(.bases)
        pitcher = text(.pitcher)
        pitcherId = text(.pitcherId)
        pitcherPitchCount = c.sportsValue(Int.self, .pitcherPitchCount)
        batter = text(.batter)
        batterId = text(.batterId)
    }
}

extension SportsBaseballSituation {
    /// Which of first, second and third are taken (Expo `baseballBases`): "Bases empty" or
    /// "Runners on 1st & 3rd" style labels only; nil when the runners aren't reported plainly.
    var occupiedBases: [Bool]? {
        guard let bases else { return nil }
        if bases == "Bases empty" { return [false, false, false] }
        let pattern = #"^(?:Runner on |Runners on |On )?(?:1st|2nd|3rd)(?: & (?:1st|2nd|3rd))*$"#
        guard bases.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return ["1st", "2nd", "3rd"].map { bases.contains($0) }
    }
}

extension SportsGame {
    /// The live football situation (Expo `detail.sport` kind `nfl`): NFL and college football
    /// while live only, as the Expo normaliser keeps it.
    var liveFootballSituation: SportsFootballSituation? {
        lifecycle == .live && (league == "nfl" || league == "college-football") ? footballSituation : nil
    }

    /// The live at-bat for MLB while live (Expo `detail.sport` kind `mlb`): the detail's, with
    /// the players' ids, before the scoreboard's.
    var liveBaseballSituation: SportsBaseballSituation? {
        lifecycle == .live && league == "mlb" ? (detail?.sport ?? liveSituation) : nil
    }

    /// The period as the page shows it (Expo `periodLabel`): none before the start, a live MLB
    /// game's half-inning from its at-bat, else the feed's period.
    var periodLabel: String? {
        switch lifecycle {
        case .scheduled: return nil
        case .live where league == "mlb": return liveSituation.flatMap { $0.inning.isEmpty ? nil : $0.inning } ?? period
        default: return period
        }
    }
}
