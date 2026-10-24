import SwiftUI

/// Tennis wording and set-score rules (Expo `sports-tennis.ts` and the set rows of
/// `SportsTennisSetScores` / `SportsTennisCard`).
enum SportsTennis {
    /// The tennis-ball accent Expo marks the set in play with (`sportsIconColor('tennis')`).
    static let accent = Color(red: 0.78, green: 0.92, blue: 0.27)

    /// The tournament, draw and round ("US Open · Men's Singles · Qualifying 1st Round"); older
    /// feeds only prefix the title with the tournament ("US Open: A vs B").
    static func eventContext(_ game: SportsGame) -> String? {
        guard game.league == "atp" || game.league == "wta" else { return nil }
        if let context = game.eventContext?.trimmingCharacters(in: .whitespaces), !context.isEmpty { return context }
        let suffix = ": \(game.awayTeam.name) vs \(game.homeTeam.name)"
        guard let title = game.title, title.hasSuffix(suffix) else { return nil }
        return String(title.dropLast(suffix.count))
    }

    /// Tiebreak points as superscript digits, a reported zero included ("⁷", "¹⁰"); nothing
    /// when not reported.
    static func tiebreak(_ points: Int?) -> String {
        guard let points, points >= 0 else { return "" }
        let digits = Array("⁰¹²³⁴⁵⁶⁷⁸⁹")
        return String(String(points).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }

    /// The last set with games reported (the one in play while live).
    static func latestSet(_ periods: [SportsPeriodScore]) -> Int? {
        periods.lastIndex { !$0.away.isEmpty || !$0.home.isEmpty }
    }

    /// A side's games in a set with its tiebreak points ("7⁵"), "–" when not reported.
    static func games(_ period: SportsPeriodScore, away: Bool) -> String {
        let value = away ? period.away : period.home
        return (value.isEmpty ? "–" : value) + tiebreak(away ? period.awayTiebreak : period.homeTiebreak)
    }

    /// Whether a side won the set (bold).
    static func won(_ period: SportsPeriodScore, away: Bool) -> Bool {
        (away ? period.awayWinner : period.homeWinner) == true
    }

    /// A player or pair ("A / B" on two lines) with the seed ("Jannik Sinner [1]").
    static func name(_ player: SportsTeam, seed: Bool = true) -> String {
        let name = player.name.isEmpty ? player.shortName : player.name
        let lines = name.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        guard seed, let value = player.displaySeed else { return lines }
        return "\(lines) [\(value)]"
    }
}
