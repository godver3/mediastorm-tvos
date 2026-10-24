import Foundation

/// Cricket's innings rules (Expo `SportsCricketOverview` and `SportsCricketScorecards`): which
/// innings is in progress, how each is labelled, the chase, and a final's top performers.
enum SportsCricket {
    /// One innings as the scorecard shows it.
    struct Line: Equatable {
        let innings: SportsCricketInnings
        let team: SportsTeam?
        let current: Bool
        let score: String
        /// "1st innings", "2nd innings", or "Match innings 3" when earlier innings are missing.
        let label: String
        /// "Batting", "Current innings" during a break, "Last reported batting" when old; else the label.
        let state: String
        /// "Target 156 · 12 runs needed".
        let chase: String
        /// Runs toward the target (0…1) while chasing.
        let progress: Double?
    }

    /// The innings, the one in progress first (only while live and when the feed names exactly one).
    static func lines(_ page: SportsGamePage) -> [Line] {
        let innings = page.lifecycle == .scheduled ? [] : page.detail.innings
        let batting = innings.filter { $0.batting == true }
        let active = page.lifecycle == .live && batting.count == 1 ? batting[0] : nil
        let ordered = active.map { a in [a] + innings.filter { $0 != a } } ?? innings
        let status = SportsFormat.detailStatus(page)
        let breakInPlay = SportsFormat.matches(#"break|stumps|rain|delay|suspend|lunch|tea\b"#, status)
        return ordered.map { row in
            let current = row == active
            let target = row.target.flatMap { $0 > 0 ? $0 : nil }
            var needed: Int?
            if current, !breakInPlay, let target, let runs = row.runs, runs >= 0, runs < target, (row.wickets ?? 0) < 10 {
                needed = target - runs
            }
            let complete = (1...4).contains(row.number) && (1...row.number).allSatisfy { n in innings.contains { $0.number == n } }
            let ordinal = innings.filter { $0.teamId == row.teamId && $0.number <= row.number }.count
            let label = complete && ordinal <= 2
                ? (ordinal == 1 ? String(localized: "1st innings") : String(localized: "2nd innings"))
                : String(localized: "Match innings \(row.number)")
            let state = !current ? label : page.isStale() ? String(localized: "Last reported batting")
                : breakInPlay ? String(localized: "Current innings") : String(localized: "Batting")
            let chase = [target.map { String(localized: "Target \($0)") },
                         needed.map { $0 == 1 ? String(localized: "1 run needed") : String(localized: "\($0) runs needed") }]
                .compactMap { $0 }.joined(separator: " · ")
            let progress = current ? target.flatMap { t in row.runs.flatMap { $0 >= 0 ? min(1, Double($0) / Double(t)) : nil } } : nil
            return Line(innings: row, team: page.team(id: row.teamId), current: current,
                        score: row.score ?? "\(row.runs.map(String.init) ?? "–")/\(row.wickets.map(String.init) ?? "–")",
                        label: label, state: state, chase: chase, progress: progress)
        }
    }

    /// A final's best batter (most runs) and bowler (most wickets) in the last innings reported;
    /// every one tied at the top, none when the best is zero.
    struct Highlight: Equatable {
        let player: SportsCricketPlayer
        let value: String
        let metric: String
    }

    static func highlights(_ page: SportsGamePage) -> (innings: Int, players: [Highlight]) {
        let cards = page.detail.cricketScorecards
        let latest = cards.map(\.innings).max() ?? 0
        guard page.lifecycle == .final else { return (latest, []) }
        let players = cards.filter { $0.innings == latest }.flatMap { card -> [Highlight] in
            let metric = card.kind == .batting ? "Runs" : "Wickets"
            let candidates = card.players.compactMap { player -> (SportsCricketPlayer, String, Double)? in
                guard let value = player.value(metric)?.trimmingCharacters(in: .whitespaces), let number = Double(value) else { return nil }
                return (player, value, number)
            }
            guard let best = candidates.map(\.2).max(), best > 0 else { return [] }
            let name = card.kind == .batting ? String(localized: "runs") : String(localized: "wickets")
            return candidates.filter { $0.2 == best }.map { Highlight(player: $0.0, value: $0.1, metric: name) }
        }
        return (latest, players)
    }
}
