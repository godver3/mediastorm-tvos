import SwiftUI

/// The Box Score / Match Stats tab (Expo `SportsPlayerStats` beside `StatsPanel`): pick a
/// side, then its players' game stats in one table per category (Passing, Rushing…), with
/// every team statistic alongside (football's split by share, Expo `FootballComparison`). When a
/// side's tables need more than two thirds of the width, the team statistics go underneath.
/// Opened on a player (MLB's Overview), it shows their side with their row marked and focused.
struct SportsBoxScore: View {
    let page: SportsGamePage
    var target: SportsPlayerTarget?

    @State private var teamID: String?
    @FocusState private var chipFocus: String?
    @FocusState private var rowFocus: String?

    var body: some View {
        boxScore
            .task(id: target) {
                guard let target else { return }
                teamID = target.teamID
                // Once the side's tables are drawn, the player's row takes focus.
                try? await Task.sleep(for: .milliseconds(150))
                rowFocus = Self.rowID(category: target.category, player: target.playerID)
            }
    }

    private static func rowID(category: String, player: String) -> String { "\(category)|\(player)" }

    @ViewBuilder private var boxScore: some View {
        let teams = page.teams.filter { team in page.detail.playerStats.contains { $0.teamId == team.id } }
        let chosen = teams.first { $0.id == teamID } ?? teams.first
        let tables = chosen.map { SportsBoxScoreTable.tables(teamID: $0.id, stats: page.detail.playerStats) } ?? []
        let comparisons = page.detail.comparisons
        // Either side's widest table decides, so the layout holds when the side changes.
        let wide = teams.flatMap { SportsBoxScoreTable.tables(teamID: $0.id, stats: page.detail.playerStats) }
            .map(\.minimumWidth).max() ?? 0 > 1040
        if teams.isEmpty && comparisons.isEmpty {
            SportsPanel(nil) {
                Text("No box score in the loaded feed.").foregroundStyle(.secondary).sportsReadout()
            }
        } else if wide || comparisons.isEmpty || teams.isEmpty {
            VStack(alignment: .leading, spacing: 36) {
                if let chosen { players(teams, chosen: chosen, tables: tables) }
                if !comparisons.isEmpty { comparison(comparisons) }
            }
        } else if let chosen {
            SportsColumns(weights: [2.15, 1]) {
                players(teams, chosen: chosen, tables: tables).focusSection()
                comparison(comparisons).focusSection()
            }
        }
    }

    /// Every team statistic, then hockey's and basketball's shooting panel (Expo `ShootingComparison`).
    private func comparison(_ rows: [SportsComparison]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            SportsTeamComparison(page: page, rows: rows, title: String(localized: "Team Comparison"),
                                 style: page.isFootballLeague ? .share : .centre)
            if !SportsShootingComparison.rows(page).isEmpty { SportsShootingComparison(page: page) }
        }
    }

    private func players(_ teams: [SportsTeam], chosen: SportsTeam, tables: [SportsBoxScoreTable]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                ForEach(teams, id: \.id) { team in
                    Button { teamID = team.id } label: {
                        HStack(spacing: 14) {
                            SportsTeamLogo(team: team, size: 36)
                            Text(team.name).lineLimit(1)
                        }
                    }
                    .buttonStyle(FilterChipStyle(selected: team.id == chosen.id))
                    .focused($chipFocus, equals: team.id)
                    .accessibilityIdentifier("sports-boxscore-team-\(team.id)")
                }
            }
            .font(.callout)
            .sportsChipRow()
            .defaultFocus($chipFocus, chosen.id, priority: .userInitiated)
            ForEach(tables) { table($0, team: chosen) }
        }
    }

    private func table(_ table: SportsBoxScoreTable, team: SportsTeam) -> some View {
        let widths = table.columnWidths
        return SportsPanel(table.category) {
            HStack(spacing: 0) {
                Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(table.columns.enumerated()), id: \.offset) { index, label in
                    Text(SportsBoxScoreTable.heading(label)).lineLimit(1).frame(width: widths[index])
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(table.rows) { row in
                HStack(spacing: 0) {
                    HStack(spacing: 14) {
                        SportsPlayerPortrait(name: row.name, headshot: row.headshotUrl, team: team, size: 44)
                        Text(row.name).lineLimit(1)
                        if let jersey = row.jersey { Text("#\(jersey)").font(.caption).foregroundStyle(.secondary) }
                        if target == SportsPlayerTarget(teamID: team.id, playerID: row.id, category: table.category) {
                            Text("Selected Player").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(Array(table.columns.enumerated()), id: \.offset) { index, label in
                        Text(row.value(label) ?? "—").lineLimit(1).frame(width: widths[index])
                    }
                }
                .monospacedDigit()
                .sportsReadout()
                .focused($rowFocus, equals: Self.rowID(category: table.category, player: row.id))
            }
        }
    }
}

/// One category of a side's box score (Expo `SportsPlayerStats` per category): its players
/// with stats, and the columns they share, in the feed's order.
struct SportsBoxScoreTable: Identifiable, Equatable {
    let category: String
    let columns: [String]
    let rows: [SportsPlayerStats]

    var id: String { category }

    static func tables(teamID: String, stats: [SportsPlayerStats]) -> [SportsBoxScoreTable] {
        var order: [String] = []
        var rows: [String: [SportsPlayerStats]] = [:]
        for row in stats where row.teamId == teamID && !row.stats.isEmpty {
            if rows[row.category] == nil { order.append(row.category) }
            rows[row.category, default: []].append(row)
        }
        return order.map { category in
            let players = rows[category] ?? []
            var columns: [String] = []
            for label in players.flatMap({ $0.stats.map(\.label) }) where !columns.contains(label) { columns.append(label) }
            return SportsBoxScoreTable(category: category, columns: columns, rows: players)
        }
    }

    /// A column's heading as Expo shows it ("SACK / YDS").
    static func heading(_ label: String) -> String { label == "SACK-YDS" ? "SACK / YDS" : label }

    var columnWidths: [CGFloat] {
        columns.map { label in SportsTable.width(label: Self.heading(label), values: rows.compactMap { $0.value(label) }) }
    }

    /// Room for the player column and every figure.
    var minimumWidth: CGFloat { 360 + columnWidths.reduce(0, +) }
}
