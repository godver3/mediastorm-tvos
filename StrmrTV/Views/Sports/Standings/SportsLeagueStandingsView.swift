import SwiftUI

/// A league's standings (Expo `SportsLeagueStandings`): the season line, a table menu when there
/// are several (conferences, divisions), the leading entry, then the table with four columns
/// chosen per kind of league; a row opens to every supplied statistic and, in a league's
/// overview, a button for that team's games. Teams with games in the selection are marked.
struct SportsLeagueStandingsView: View {
    @ObservedObject var model: SportsStandingsModel
    var fixtureTeamIDs: Set<String> = []
    var selectedTeamID: String?
    var onTeamSelect: ((SportsTableRow) -> Void)?

    var body: some View {
        let data = model.standings
        VStack(alignment: .leading, spacing: 18) {
            SportsSectionHeading(title: String(localized: "Standings"))
            if data == nil && !model.failed {
                SportsNotice(title: String(localized: "Loading standings"),
                             message: String(localized: "Fetching the provider's league table."), loading: true)
            }
            if model.failed || data?.delayed == true {
                SportsNotice(title: (data?.groups ?? []).isEmpty ? String(localized: "Standings unavailable")
                                : String(localized: "Standings updates delayed"),
                             message: data?.reason.flatMap { $0.isEmpty ? nil : $0 }
                                ?? String(localized: "Any displayed table is from the last successful update."),
                             retry: model.retry)
            }
            if let data, let table = model.table {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(table.seasonLabel) · Provider table season \(String(table.season))")
                    Text("Season tables are independent of the selected event date.")
                }
                .font(.caption).foregroundStyle(.secondary)
                if data.groups.count > 1 { groupMenu(data.groups, table) }
                Text(table.title).font(.headline)
                if let leader = SportsStandings.leader(table) { leaderBox(leader, table) }
                tablePanel(table)
                Text(fixtureTeamIDs.isEmpty ? "Select a row for full supplied statistics."
                     : "Marked teams have games in this selection. Select a row for full statistics.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let data, let updated = data.updatedAt.flatMap(SportsGame.date) {
                Text("\(data.source.isEmpty ? "ESPN" : data.source) · \(SportsRaceFormat.checked(updated))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .task(id: "\(model.league)|\(model.retries)") { await model.poll() }
    }

    private func groupMenu(_ groups: [SportsLeagueTable], _ table: SportsLeagueTable) -> some View {
        let label = SportsStandings.groupLabel(model.league)
        return Menu {
            Picker(label, selection: Binding(get: { table.id }, set: { model.choose($0) })) {
                ForEach(groups) { Text($0.title).tag($0.id) }
            }
        } label: {
            Label("\(label): \(table.title)", systemImage: "chevron.down").lineLimit(1)
        }
        .sportsChipRow()
        .accessibilityIdentifier("sports-standings-group")
    }

    /// The leading entry (Expo's leader box): "LEADING ENTRY · SEED 1", the name, points and record.
    private func leaderBox(_ row: SportsTableRow, _ table: SportsLeagueTable) -> some View {
        SportsPanel(nil) {
            VStack(alignment: .leading, spacing: 4) {
                SportsEyebrow(text: SportsStandings.leaderEyebrow(row))
                Text(row.name).font(.title3.weight(.bold))
                let summary = SportsStandings.leaderSummary(row, table)
                if !summary.isEmpty { Text(summary).font(.callout.weight(.semibold)) }
            }
            .sportsReadout()
        }
    }

    private func tablePanel(_ table: SportsLeagueTable) -> some View {
        let columns = SportsStandings.columns(model.league, table)
        return SportsPanel(nil) {
            HStack(spacing: 0) {
                SportsColumnHeading(String(localized: "Team / Competitor")).padding(.leading, 20)
                ForEach(columns, id: \.key) { SportsColumnHeading($0.label, alignment: .trailing).frame(width: Self.width($0.key)) }
            }
            ForEach(table.rows) { row in
                tableRow(row, table: table, columns: columns)
                if model.expandedID == row.id, let onTeamSelect, row.kind == "team" {
                    Button(String(localized: "Show \(row.abbreviation.flatMap { $0.isEmpty ? nil : $0 } ?? row.name) Games")) {
                        onTeamSelect(row)
                    }
                    .padding(.leading, 20)
                    .accessibilityIdentifier("sports-standings-show-games")
                }
            }
        }
    }

    private func tableRow(_ row: SportsTableRow, table: SportsLeagueTable, columns: [SportsTableColumn]) -> some View {
        let marked = row.id == selectedTeamID || fixtureTeamIDs.contains(row.id)
        let open = model.expandedID == row.id
        return Button { model.expandedID = open ? nil : row.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    Capsule().fill(marked ? SportsStatusPill.accent : .clear).frame(width: 5, height: 28)
                    Text(row.name).font(.callout.weight(marked ? .bold : .semibold)).lineLimit(1)
                        .padding(.leading, 15).frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(columns, id: \.key) { column in
                        Text(SportsStandings.value(row, column.key)).font(.callout).monospacedDigit().lineLimit(1)
                            .frame(width: Self.width(column.key), alignment: .trailing)
                    }
                }
                if open {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .leading)], alignment: .leading, spacing: 4) {
                        ForEach(table.columns, id: \.key) { column in
                            SportsReading("\(column.label):", SportsStandings.value(row, column.key))
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .buttonStyle(SportsReadoutButtonStyle(chosen: open))
        .accessibilityIdentifier("sports-standings-row-\(row.id)")
    }

    /// A record ("8-2-2, 18 PTS") needs more room than a seed or a percentage.
    private static func width(_ key: String) -> CGFloat { key == "overall" ? 230 : 110 }
}
