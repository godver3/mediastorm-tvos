#if os(iOS)
import SwiftUI

/// The Box Score / Match Stats tab on a phone (Expo `SportsPlayerStats` with `StatsPanel`): a
/// segmented control for the side, then one table per category (Passing, Rushing…) whose player
/// column stays put while the figures scroll sideways, then every team statistic
/// (`SportsTeamComparison`, football's split by share) and the shooting panel. Opened on a player
/// (MLB's Overview), it shows their side with their row marked.
struct MobileSportsBoxScore: View {
    let page: SportsGamePage
    var target: SportsPlayerTarget?

    @State private var teamID: String?

    var body: some View {
        let teams = page.teams.filter { team in page.detail.playerStats.contains { $0.teamId == team.id } }
        let chosen = teams.first { $0.id == teamID } ?? teams.first
        let comparisons = page.detail.comparisons
        VStack(alignment: .leading, spacing: 16) {
            if teams.isEmpty && comparisons.isEmpty {
                ContentUnavailableView("No Box Score", systemImage: "tablecells", description: Text("No box score in the loaded feed."))
            }
            if let chosen {
                if teams.count > 1 {
                    Picker("Team", selection: Binding(get: { chosen.id }, set: { teamID = $0 })) {
                        ForEach(teams, id: \.id) { Text($0.shortName).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("sports-boxscore-team")
                }
                ForEach(SportsBoxScoreTable.tables(teamID: chosen.id, stats: page.detail.playerStats)) { table in
                    MobileSportsStatTable(table: table, team: chosen, target: target)
                }
            }
            if !comparisons.isEmpty {
                SportsTeamComparison(page: page, rows: comparisons, title: String(localized: "Team Comparison"),
                                     style: page.isFootballLeague ? .share : .centre)
            }
            if !SportsShootingComparison.rows(page).isEmpty { SportsShootingComparison(page: page) }
        }
        .task(id: target) {
            if let target { teamID = target.teamID }
        }
    }
}

/// One category of a side's box score: the players down the left, their figures in a grid that
/// scrolls sideways.
struct MobileSportsStatTable: View {
    let table: SportsBoxScoreTable
    let team: SportsTeam
    let target: SportsPlayerTarget?

    private static let rowHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(table.category).font(.headline).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Player").font(.caption).foregroundStyle(.secondary).frame(height: 28, alignment: .leading)
                    ForEach(table.rows) { row in
                        HStack(spacing: 8) {
                            SportsPlayerPortrait(name: row.name, headshot: row.headshotUrl, team: team, size: 26)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(row.name).font(.subheadline.weight(selected(row) ? .bold : .regular)).lineLimit(1)
                                if let jersey = row.jersey {
                                    Text("#\(jersey)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: Self.rowHeight, alignment: .leading)
                    }
                }
                .frame(width: 150, alignment: .leading)
                ScrollView(.horizontal) {
                    Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 0) {
                        GridRow {
                            ForEach(Array(table.columns.enumerated()), id: \.offset) { _, label in
                                Text(SportsBoxScoreTable.heading(label)).font(.caption).foregroundStyle(.secondary)
                                    .frame(height: 28)
                            }
                        }
                        ForEach(table.rows) { row in
                            GridRow {
                                ForEach(Array(table.columns.enumerated()), id: \.offset) { _, label in
                                    Text(row.value(label) ?? "—").font(.subheadline).monospacedDigit()
                                        .fontWeight(selected(row) ? .bold : .regular)
                                        .frame(minWidth: 28, alignment: .trailing)
                                        .frame(height: Self.rowHeight)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func selected(_ row: SportsPlayerStats) -> Bool {
        target == SportsPlayerTarget(teamID: team.id, playerID: row.id, category: table.category)
    }
}

/// The Standings tab on a phone (Expo `SportsStandingsPanel`): the table sent with the game, one
/// group at a time from a menu when there are several, this game's sides in bold. Soccer shows
/// played, goal difference and points; others conference and overall records.
struct MobileSportsGameStandings: View {
    let page: SportsGamePage

    @State private var groupIndex = 0

    var body: some View {
        let groups = page.detail.standings
        let index = groups.indices.contains(groupIndex) ? groupIndex : 0
        let soccer = page.kind == .soccer
        VStack(alignment: .leading, spacing: 12) {
            if groups.count > 1 {
                Picker("Group", selection: $groupIndex) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { offset, group in
                        Text(SportsStandingsPanel.chipLabel(group.title)).tag(offset)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("sports-standings-group")
            }
            if groups.indices.contains(index) {
                let group = groups[index]
                SportsPanel(group.title.isEmpty ? String(localized: "Standings") : group.title,
                            note: String(localized: "Table snapshot supplied with the feed · May be newer than this game")) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        GridRow {
                            Text("#")
                            Text("Team").frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(soccer ? ["GP", "GD", "PTS"] : ["CONF", "OVR"], id: \.self) {
                                Text($0).gridColumnAlignment(.trailing)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, team in
                            let playing = team.teamId == page.game.homeTeam.id || team.teamId == page.game.awayTeam.id
                            let values = soccer ? [team.played, team.goalDifference, team.points] : [team.conferenceRecord, team.record]
                            GridRow {
                                Text(team.rank ?? "–").foregroundStyle(.secondary)
                                Text(team.name).lineLimit(1)
                                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                                    Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "–")
                                }
                            }
                            .fontWeight(playing ? .bold : .regular)
                            .monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    Text(soccer ? "GP: games played · GD: goal difference · PTS: points."
                         : "CONF: conference record · OVR: overall record.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
#endif
