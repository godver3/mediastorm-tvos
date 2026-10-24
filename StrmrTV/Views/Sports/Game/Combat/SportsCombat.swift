import Foundation

/// Fight wording and rules (Expo `sports-combat-card.ts`): a fighter's portrait, a bout's result
/// line, and which statistics can be compared with bars.
enum SportsCombatRules {
    /// The feed's portrait, or ESPN's MMA headshot for a UFC fighter id (never for boxing ids);
    /// team logos are not portraits.
    static func portrait(league: String, fighter: SportsTeam) -> String? {
        if let logo = fighter.logoUrl, !logo.isEmpty, !SportsFormat.matches(#"/teamlogos/"#, logo) { return logo }
        guard league == "ufc", !fighter.id.isEmpty, fighter.id.allSatisfy(\.isNumber) else { return nil }
        return "https://a.espncdn.com/i/headshots/mma/players/full/\(fighter.id).png"
    }

    /// Both fighters are named (a schedule-only boxing card is not).
    static func named(_ game: SportsGame) -> Bool { !game.awayTeam.name.isEmpty && !game.homeTeam.name.isEmpty }

    /// "Diego Lopes wins · Round 2 · 4:48", the round and clock while live ("Live bout"), the
    /// state otherwise; "Result hidden" with scores hidden.
    static func result(lifecycle: SportsLifecycle, away: SportsTeam, home: SportsTeam, detail: String?,
                       period: String?, clock: String?, hidden: Bool) -> String {
        if hidden { return String(localized: "Result hidden") }
        switch lifecycle {
        case .scheduled: return String(localized: "Scheduled")
        case .postponed: return String(localized: "Postponed")
        case .canceled: return String(localized: "Canceled")
        case .delayed: return String(localized: "Delayed")
        case .live:
            let parts = [period, clock].compactMap { $0 }.filter { !$0.isEmpty && !SportsFormat.matches(#"^[-–—]+$"#, $0) }
            return parts.isEmpty ? String(localized: "Live bout") : parts.joined(separator: " · ")
        case .final:
            let winner = (away.winner == true) != (home.winner == true) ? (away.winner == true ? away : home) : nil
            let reported = detail?.trimmingCharacters(in: .whitespaces)
            return [winner.map { String(localized: "\($0.name) wins") } ?? String(localized: "Result not supplied"),
                    reported.flatMap { $0.isEmpty || SportsFormat.matches("^final$", $0) ? nil : $0 }, period, clock]
                .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        }
    }

    /// The game's own result line.
    static func result(_ game: SportsGame, hidden: Bool) -> String {
        result(lifecycle: game.lifecycle, away: game.awayTeam, home: game.homeTeam, detail: game.statusDetail,
               period: game.period, clock: game.clock, hidden: hidden)
    }

    /// A bout's line on the fight card (its division, then the result).
    static func result(_ bout: SportsCombatBout, hidden: Bool) -> String? {
        hidden ? nil : result(lifecycle: bout.lifecycle, away: bout.away, home: bout.home, detail: nil,
                              period: bout.period, clock: bout.clock, hidden: false)
    }

    /// Comparable totals (control time as seconds); ratios, percentages and missing values get
    /// no bars.
    static func barValues(label: String, away: String, home: String) -> (Double, Double)? {
        func parse(_ value: String) -> Double? {
            let raw = value.trimmingCharacters(in: .whitespaces)
            if SportsFormat.matches("control time", label) {
                let parts = raw.split(separator: ":")
                guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]), parts[1].count == 2,
                      seconds < 60 else { return nil }
                return Double(minutes * 60 + seconds)
            }
            return SportsFormat.matches(#"^\d+(\.\d+)?$"#, raw) ? Double(raw) : nil
        }
        guard let a = parse(away), let b = parse(home) else { return nil }
        return (a, b)
    }

    /// The tale of the tape: height, reach, weight and stance from both fighters' profiles.
    static func tape(_ page: SportsGamePage) -> [(label: String, away: String?, home: String?)] {
        let profile = { (team: SportsTeam) in page.detail.fighterProfiles.first { $0.id == team.id } }
        let away = profile(page.game.awayTeam), home = profile(page.game.homeTeam)
        return ["Height", "Reach", "Weight", "Stance"].compactMap { label in
            let a = away?.value(label).flatMap { $0.isEmpty ? nil : $0 }
            let h = home?.value(label).flatMap { $0.isEmpty ? nil : $0 }
            guard a != nil || h != nil else { return nil }
            return (SportsCombatRules.tapeLabels[label] ?? label, a, h)
        }
    }

    private static let tapeLabels = [
        "Height": String(localized: "Height"), "Reach": String(localized: "Reach"),
        "Weight": String(localized: "Weight"), "Stance": String(localized: "Stance"),
    ]
}
