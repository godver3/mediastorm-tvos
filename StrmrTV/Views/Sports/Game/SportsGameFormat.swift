import Foundation

/// The game page's wording of a game's state (Expo `formatDetailStatus`, `formatGameResult`,
/// `getSportsPregameState` and `formatSportsFreshness`).
extension SportsFormat {
    /// "Fri, Oct 23".
    static func startDate(_ game: SportsGame) -> String {
        game.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// The scoreboard's state line: hockey periods and overtime, soccer halves and extra time,
    /// cricket's reported state, the period and clock while live, the start before it.
    static func detailStatus(_ page: SportsGamePage, stale: Bool = false) -> String {
        let game = page.game
        let lifecycle = game.lifecycle
        let period = game.periodLabel ?? ""
        let clock = (lifecycle == .live && game.league != "mlb") || (lifecycle == .final && page.kind == .mma) ? game.clock : nil
        let detail = game.statusDetail ?? ""
        let delayed = stale ? String(localized: "Updates delayed") : nil
        let join = { (parts: [String?]) in parts.compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ") }

        if page.kind == .cricket, lifecycle != .scheduled {
            let reported = [detail, period].map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
            return join([reported ?? fallback(lifecycle), delayed])
        }
        if game.league == "nhl", lifecycle == .live || lifecycle == .final {
            let supplied = "\(period) \(detail)"
            let shootout = matches(#"\bSO\b|shootout"#, supplied)
            let overtime = matches(#"\b(?:\d+OT|OT\d*)\b|overtime"#, supplied)
            let intermission = matches(#"intermission|\bINT\b"#, supplied)
            if lifecycle == .final {
                let suffix = shootout ? String(localized: "Shootout") : overtime ? String(localized: "Overtime") : nil
                return join([String(localized: "Final"), suffix, delayed])
            }
            let label = shootout ? String(localized: "Shootout")
                : intermission ? String(localized: "Intermission")
                : overtime ? (matches(#"\d+OT|OT\d+"#, period) ? String(localized: "Overtime · \(period)") : String(localized: "Overtime"))
                : (hockeyPeriods[period] ?? period)
            return join([label.isEmpty ? String(localized: "Live") : label, shootout || intermission ? nil : clock, delayed])
        }
        if page.kind == .soccer, lifecycle == .live || lifecycle == .final {
            if lifecycle == .final {
                let supplied = "\(period) \(detail)"
                let shootout = game.awayTeam.shootoutScore != nil || game.homeTeam.shootoutScore != nil
                let status = matches(#"\b(?:PEN|PK)\b|penalt"#, supplied) || shootout ? String(localized: "Full time · Penalties")
                    : matches(#"\b(?:ET[12]?|AET)\b|extra time"#, supplied) ? String(localized: "Full time · After extra time")
                    : String(localized: "Full time")
                return join([status, delayed])
            }
            let stopped = matches(#"^(HT|halftime|half time|PEN|PK)$"#, period)
            let status = join([soccerPeriods[period.uppercased()] ?? period, stopped ? nil : clock])
            return join([status.isEmpty ? String(localized: "Live") : status, delayed])
        }
        switch lifecycle {
        case .live:
            let collegeOvertime = game.league == "college-football" && matches(#"\b(?:\d+OT|OT\d*)\b|overtime"#, period)
            let status = join([period, collegeOvertime ? nil : clock])
            return status.isEmpty ? String(localized: "Live") : status
        case .scheduled:
            return join([startDate(game), game.start.formatted(date: .omitted, time: .shortened)])
        default:
            return detail.isEmpty ? join([lifecycle.pill, period]) : detail
        }
    }

    /// "Chicago Bears win", "… win 4–3 on penalties", or "Draw" for a level soccer final.
    static func result(_ page: SportsGamePage) -> String? {
        let game = page.game
        guard game.lifecycle == .final else { return nil }
        let away = game.awayTeam, home = game.homeTeam
        if (away.winner == true) != (home.winner == true) {
            let (winner, loser) = away.winner == true ? (away, home) : (home, away)
            if let won = winner.shootoutScore, let lost = loser.shootoutScore {
                return String(localized: "\(winner.name) win \(won)–\(lost) on penalties")
            }
            return String(localized: "\(winner.name) win")
        }
        if page.kind == .soccer, let score = away.score, !score.isEmpty, score == home.score,
           away.shootoutScore == nil, home.shootoutScore == nil {
            return String(localized: "Draw")
        }
        return nil
    }

    /// Within 15 minutes of a scheduled start (Expo `SportsPregameNotice`): "Starts in 12:04"
    /// counting down, then "Starting soon" once the start has passed.
    static func pregameCountdown(_ game: SportsGame, now: Date = Date()) -> String? {
        guard game.lifecycle == .scheduled, game.start != .distantPast else { return nil }
        let remaining = game.start.timeIntervalSince(now)
        if remaining < 0 { return String(localized: "Starting soon") }
        guard remaining <= 15 * 60 else { return nil }
        let seconds = Int(remaining.rounded(.up))
        return String(localized: "Starts in \(seconds / 60):\(String(format: "%02d", seconds % 60))")
    }

    /// The page's footer (Expo `formatSportsFreshness`).
    static func freshness(_ page: SportsGamePage, stale: Bool) -> String {
        if stale { return String(localized: "Scores may be delayed") }
        guard let updated = page.detail.updatedAt.flatMap(SportsGame.date) else { return String(localized: "Update time unavailable") }
        return String(localized: "Feed checked \(updated.formatted(date: .abbreviated, time: .shortened))")
    }

    private static func fallback(_ lifecycle: SportsLifecycle) -> String {
        switch lifecycle {
        case .live: String(localized: "Live")
        case .final: String(localized: "Final")
        default: lifecycle.pill.capitalized
        }
    }

    private static let hockeyPeriods = [
        "P1": String(localized: "1st period"), "P2": String(localized: "2nd period"), "P3": String(localized: "3rd period"),
    ]

    private static let soccerPeriods = [
        "HT": String(localized: "Halftime"), "H1": String(localized: "First half"), "H2": String(localized: "Second half"),
        "ET1": String(localized: "Extra time · First half"), "ET2": String(localized: "Extra time · Second half"),
        "ET": String(localized: "Extra time"), "PEN": String(localized: "Penalty shootout"),
        "PK": String(localized: "Penalty shootout"), "FT": String(localized: "Full time"),
    ]

    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
