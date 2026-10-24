import Foundation

/// Whether an MLB at-bat is under way and how it stands (Expo `baseballState`): only a reported,
/// active half-inning (the top or bottom of one; not a break, a delay, a pitching change or the
/// third out) has a batting and a pitching side, a count and outs. Otherwise `status` says why.
/// Works from a scoreboard game too (its `liveSituation`), for the hub's cards.
struct SportsBaseballState: Equatable {
    let situation: SportsBaseballSituation?
    let active: Bool
    /// The inning number of the half-inning label.
    let inning: Int?
    let batting: SportsTeam?
    let pitching: SportsTeam?
    /// "Count 3–2" and "2 outs", while active and plainly reported.
    let count: String?
    let outs: String?
    /// The break or delay reported, "Half-inning complete" or "No active at-bat reported".
    let status: String

    init(game: SportsGame) {
        let situation = game.liveBaseballSituation
        let phase = game.periodLabel.flatMap { $0.isEmpty ? nil : $0 } ?? situation?.inning ?? ""
        let stopped = SportsFormat.matches(Self.stops + #"|final"#, "\(phase) \(game.statusDetail ?? "") \(situation?.inning ?? "")")
        let half = phase.firstMatch(of: #/^(top|bottom|bot)\b/#.ignoresCase()).map { $0.1.lowercased() }
        let active = game.lifecycle == .live && !stopped && half != nil && situation != nil && situation?.outs != 3
        self.situation = situation
        self.active = active
        inning = phase.firstMatch(of: #/\d+/#).flatMap { Int($0.0) }.flatMap { $0 == 0 ? nil : $0 }
        batting = active ? (half == "top" ? game.awayTeam : game.homeTeam) : nil
        pitching = active ? (half == "top" ? game.homeTeam : game.awayTeam) : nil
        let valid = { (value: Int?, top: Int) in value.flatMap { (0...top).contains($0) ? $0 : nil } }
        if active, let balls = valid(situation?.balls, 3), let strikes = valid(situation?.strikes, 2) {
            count = String(localized: "Count \(balls)–\(strikes)")
        } else {
            count = nil
        }
        outs = active ? valid(situation?.outs, 2).map(Self.outs) : nil
        let transition = [game.statusDetail, phase, situation?.inning]
            .compactMap { $0 }.first { !$0.isEmpty && SportsFormat.matches(Self.stops, $0) }
        status = transition ?? (situation?.outs == 3 ? String(localized: "Half-inning complete") : String(localized: "No active at-bat reported"))
    }

    /// Breaks in play: between or after half-innings, delays, suspensions, pitching changes.
    private static let stops = #"middle|mid\b|end\b|delay|suspend|postpon|break|pitching change|pitcher change"#

    static func outs(_ count: Int) -> String {
        count == 1 ? String(localized: "1 out") : String(localized: "\(count) outs")
    }

    /// The scoreboard's line under the inning (Expo `BaseballSituationLine`): "2 outs · Count 3–2",
    /// "Last reported · …" when the data is old; nil when no at-bat is under way.
    func scoreboardLine(stale: Bool) -> String? {
        guard active else { return nil }
        let shown = [outs, count].compactMap { $0 }
        guard !shown.isEmpty else { return nil }
        return ((stale ? [String(localized: "Last reported")] : []) + shown).joined(separator: " · ")
    }
}

/// MLB's line score (Expo `SportsPeriodBreakdown` for MLB): at least nine innings (more for extra
/// innings or the one being played), then runs, hits and errors for each side.
struct SportsBaseballLineScore: Equatable {
    struct Inning: Equatable {
        let number: Int
        let away: String
        let home: String
    }

    struct Total: Equatable {
        let label: String
        let away: String
        let home: String
    }

    let innings: [Inning]
    let totals: [Total]
    /// The inning being played, while an at-bat is under way.
    let current: Int?

    init(page: SportsGamePage) {
        let state = SportsBaseballState(game: page.game)
        let periods = page.detail.periods
        let count = max(9, state.inning ?? 0, periods.compactMap { Int($0.label) }.max() ?? 0)
        let shown = { (value: String?) in value.flatMap { $0.isEmpty ? nil : $0 } ?? "–" }
        innings = (1...count).map { number in
            let period = periods.first { Int($0.label) == number }
            return Inning(number: number, away: shown(period?.away), home: shown(period?.home))
        }
        let stat = { (label: String) in page.detail.comparisons.first { $0.label == label } }
        totals = [Total(label: "R", away: shown(page.game.awayTeam.score), home: shown(page.game.homeTeam.score)),
                  Total(label: "H", away: shown(stat("Hits")?.away), home: shown(stat("Hits")?.home)),
                  Total(label: "E", away: shown(stat("Errors")?.away), home: shown(stat("Errors")?.home))]
        current = state.active ? state.inning : nil
    }
}
