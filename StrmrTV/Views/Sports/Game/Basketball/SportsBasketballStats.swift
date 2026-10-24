import SwiftUI

/// Basketball's key team statistics (Expo `SportsBasketballOverviewStats`, "Team comparison"):
/// shooting as a percentage over made–attempted, then 3-pointers, free throws, rebounds, assists
/// and turnovers, home on the left in the chart colours. One stop per row.
struct SportsBasketballTeamStats: View {
    let page: SportsGamePage

    struct Row: Equatable {
        let label: String
        let away: String
        let home: String
        /// "39-87" under a percentage.
        var awayAttempts: String?
        var homeAttempts: String?
    }

    private static let priorities: [(label: String, match: String, percentage: String?)] = [
        (String(localized: "Field goals"), #"^field goals?$"#, #"^field goal %|field goal percentage|fg%$"#),
        (String(localized: "3-pointers"), #"three.point|three pointer|3pt"#, nil),
        (String(localized: "Free throws"), #"^free throws?$"#, nil),
        (String(localized: "Rebounds"), #"^(total )?rebounds$"#, nil),
        (String(localized: "Assists"), #"^assists$"#, nil),
        (String(localized: "Turnovers"), #"^(total )?turnovers$"#, nil),
    ]

    /// Expo `basketballOverviewComparisons`.
    static func rows(_ comparisons: [SportsComparison]) -> [Row] {
        priorities.compactMap { priority in
            let row = comparisons.first { SportsFormat.matches(priority.match, $0.label) }
            let percent = priority.percentage.flatMap { pattern in comparisons.first { SportsFormat.matches(pattern, $0.label) } }
            if let percent {
                let shown = { (value: String) in value.hasSuffix("%") ? value : value + "%" }
                return Row(label: priority.label, away: shown(percent.away), home: shown(percent.home),
                           awayAttempts: row?.away, homeAttempts: row?.home)
            }
            return row.map { Row(label: priority.label, away: $0.away, home: $0.home) }
        }
    }

    var body: some View {
        let game = page.game
        let colors = SportsTeamColors.chartPair(away: game.awayTeam, home: game.homeTeam)
        SportsPanel(String(localized: "Team Comparison")) {
            HStack(spacing: 12) {
                SportsTeamLogo(team: game.homeTeam, size: 40)
                Text(game.homeTeam.shortName).foregroundStyle(Color(hex: colors.home) ?? .primary)
                Spacer()
                Text(game.awayTeam.shortName).foregroundStyle(Color(hex: colors.away) ?? .primary)
                SportsTeamLogo(team: game.awayTeam, size: 40)
            }
            .fontWeight(.semibold)
            ForEach(Self.rows(page.detail.comparisons), id: \.label) { row in
                SportsColumns(weights: [1, 1.4, 1], spacing: 12) {
                    figure(row.home, attempts: row.homeAttempts, alignment: .leading)
                    Text(row.label).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    figure(row.away, attempts: row.awayAttempts, alignment: .trailing)
                }
                .sportsReadout()
                .accessibilityLabel("\(row.label), \(game.homeTeam.shortName) \(row.home), \(game.awayTeam.shortName) \(row.away)")
            }
        }
    }

    private func figure(_ value: String, attempts: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            if let attempts { Text(attempts).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// Each side's top scorer from the box score (Expo `SportsBasketballScoringLeaders`): headshot,
/// name and "PHI · 32 PTS · 5 REB · 6 AST", home first, side by side.
struct SportsBasketballScoringLeaders: View {
    let page: SportsGamePage

    struct Leader: Equatable {
        let team: SportsTeam
        let player: SportsPlayerStats
    }

    /// Players with a plain points figure, the highest per side (the feed's first wins a tie).
    static func leaders(_ page: SportsGamePage) -> [Leader] {
        [page.game.homeTeam, page.game.awayTeam].compactMap { team in
            let points = { (player: SportsPlayerStats) in player.value("PTS").flatMap { Int($0) } ?? -1 }
            let players = page.detail.playerStats.filter { $0.teamId == team.id && points($0) >= 0 }
            let best = players.enumerated().max { a, b in
                points(a.element) != points(b.element) ? points(a.element) < points(b.element) : a.offset > b.offset
            }
            return best.map { Leader(team: team, player: $0.element) }
        }
    }

    var body: some View {
        SportsPanel(String(localized: "Scoring Leaders")) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(Self.leaders(page), id: \.team.id) { leader in
                    HStack(spacing: 16) {
                        SportsPlayerPortrait(name: leader.player.name, headshot: leader.player.headshotUrl, team: leader.team, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(leader.player.name).fontWeight(.semibold).lineLimit(1)
                            Text(([leader.team.shortName] + ["PTS", "REB", "AST"].compactMap { label in
                                leader.player.value(label).map { "\($0) \(label)" }
                            }).joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .sportsReadout()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
