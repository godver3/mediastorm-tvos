#if os(iOS)
import SwiftUI

/// The hub's Competition Details on a phone (Expo `SportsHubTV`'s details view): the cycling
/// calendar or the race weekends (the TV's `SportsCyclingCalendar` and `SportsRacingCalendar`,
/// stacked), or a team competition's standings (`MobileSportsLeagueStandings`) and the hub day's
/// games of the league, a team's games once its row is picked.
struct MobileSportsCompetitionView: View {
    let route: SportsCompetitionRoute
    @ObservedObject var hub: SportsHubStore

    @StateObject private var standings: SportsStandingsModel
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section = Section.standings
    @State private var team: (id: String, name: String)?

    enum Section: String, CaseIterable, Identifiable {
        case standings, games
        var id: String { rawValue }
        var label: String { self == .standings ? String(localized: "Standings") : String(localized: "Games") }
    }

    init(route: SportsCompetitionRoute, hub: SportsHubStore) {
        self.route = route
        self.hub = hub
        _standings = StateObject(wrappedValue: SportsStandingsModel(league: route.league))
    }

    var body: some View {
        let chosen = hub.leagues[route.league]
        MobileSportsScroll {
            VStack(alignment: .leading, spacing: 16) {
                if route.sport == SportsCycling.sport {
                    SportsCyclingCalendar(hub: hub)
                } else if route.sport == SportsHubFilters.motorsport || chosen?.isRacing == true {
                    SportsRacingCalendar(hub: hub, initialSeries: chosen?.isRacing == true ? route.league : nil)
                } else {
                    Picker("Section", selection: $section) {
                        ForEach(Section.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if section == .standings {
                        MobileSportsLeagueStandings(model: standings, fixtureTeamIDs: fixtureTeamIDs, selectedTeamID: team?.id) { row in
                            team = (row.id, row.name)
                            section = .games
                        }
                    } else {
                        games
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .environment(\.sportsStacksColumns, sizeClass == .compact)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        if route.sport == SportsCycling.sport { return String(localized: "Cycling") }
        if route.league == SportsHubFilters.all { return SportsHubFilters.sportLabel(route.sport) }
        return hub.leagueName(route.league)
    }

    private var leagueGames: [SportsGame] { hub.games.filter { $0.league == route.league } }

    private var fixtureTeamIDs: Set<String> { Set(leagueGames.flatMap { [$0.awayTeam.id, $0.homeTeam.id] }) }

    @ViewBuilder private var games: some View {
        let games = leagueGames.filter { team == nil || $0.awayTeam.id == team?.id || $0.homeTeam.id == team?.id }
            .map { game in standings.standings.map { SportsStandings.withRecords(game, $0.groups) } ?? game }
            .sorted(by: Self.fixtureOrder)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(team?.name ?? String(localized: "Games")).font(.title3.weight(.semibold))
                Text("\(hub.day.label) · \(hub.leagueName(route.league))").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if team != nil {
                Button("All Teams") { team = nil }.buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("sports-show-all-teams")
            }
        }
        if games.isEmpty {
            ContentUnavailableView("No Games", systemImage: "calendar",
                                   description: Text(team != nil ? "No games for this team in the current selection."
                                                     : "No games in this selection. The league table remains available."))
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(games) { game in
                MobileSportsHubCard(item: .game(game), store: hub, spoilers: spoilers.hidden)
            }
        }
    }

    private static func fixtureOrder(_ a: SportsGame, _ b: SportsGame) -> Bool {
        func priority(_ game: SportsGame) -> Int {
            switch game.lifecycle {
            case .live: 0
            case .scheduled: 1
            default: 2
            }
        }
        if priority(a) != priority(b) { return priority(a) < priority(b) }
        if a.lifecycle == .final && b.lifecycle == .final { return a.start > b.start }
        return a.start < b.start
    }
}

/// A league's standings on a phone (Expo `SportsLeagueStandings`): the season, a table menu when
/// there are several (conferences, divisions), the leading entry, then the table in a grid with
/// the kind of league's four columns. Tapping a row shows every supplied statistic and, in a
/// competition's details, a button for that team's games. Teams with games in the selection are
/// marked.
struct MobileSportsLeagueStandings: View {
    @ObservedObject var model: SportsStandingsModel
    var fixtureTeamIDs: Set<String> = []
    var selectedTeamID: String?
    var onTeamSelect: ((SportsTableRow) -> Void)?

    var body: some View {
        let data = model.standings
        VStack(alignment: .leading, spacing: 12) {
            if data == nil && !model.failed {
                ProgressView("Loading standings").frame(maxWidth: .infinity).padding(.vertical, 40)
            }
            if model.failed || data?.delayed == true {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((data?.groups ?? []).isEmpty ? "Standings unavailable" : "Standings updates delayed").fontWeight(.semibold)
                        Text(data?.reason.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Any displayed table is from the last successful update."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(SportsStatusPill.amber)
                }
                Button("Try Again", action: model.retry).buttonStyle(.bordered).controlSize(.small)
            }
            if let data, let table = model.table {
                if data.groups.count > 1 {
                    Picker(SportsStandings.groupLabel(model.league), selection: Binding(get: { table.id }, set: { model.choose($0) })) {
                        ForEach(data.groups) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("sports-standings-group")
                }
                if let leader = SportsStandings.leader(table) { leaderBox(leader, table) }
                tableCard(table)
                Text("\(table.seasonLabel) · Season tables are independent of the selected day.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let data, let updated = data.updatedAt.flatMap(SportsGame.date) {
                Text("\(data.source.isEmpty ? "ESPN" : data.source) · \(SportsRaceFormat.checked(updated))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .task(id: "\(model.league)|\(model.retries)") { await model.poll() }
    }

    private func leaderBox(_ row: SportsTableRow, _ table: SportsLeagueTable) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SportsEyebrow(text: SportsStandings.leaderEyebrow(row))
            Text(row.name).font(.title3.weight(.bold))
            let summary = SportsStandings.leaderSummary(row, table)
            if !summary.isEmpty { Text(summary).font(.subheadline.weight(.semibold)) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .accessibilityElement(children: .combine)
    }

    private func tableCard(_ table: SportsLeagueTable) -> some View {
        let columns = SportsStandings.columns(model.league, table)
        return VStack(alignment: .leading, spacing: 0) {
            Text(table.title).font(.headline).padding(.bottom, 8)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow {
                    Text("Team")
                    ForEach(columns, id: \.key) { Text($0.label.uppercased()).gridColumnAlignment(.trailing) }
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 6)
                ForEach(table.rows) { row in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow { tableRow(row, columns: columns) }
                        .contentShape(Rectangle())
                        .onTapGesture { model.expandedID = model.expandedID == row.id ? nil : row.id }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("sports-standings-row-\(row.id)")
                    if model.expandedID == row.id {
                        GridRow { expanded(row, table: table).gridCellColumns(columns.count + 1) }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    @ViewBuilder private func tableRow(_ row: SportsTableRow, columns: [SportsTableColumn]) -> some View {
        let marked = row.id == selectedTeamID || fixtureTeamIDs.contains(row.id)
        HStack(spacing: 6) {
            Circle().fill(marked ? SportsStatusPill.accent : .clear).frame(width: 6, height: 6)
            Text(row.name).font(.subheadline.weight(marked ? .bold : .regular)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        ForEach(columns, id: \.key) { column in
            Text(SportsStandings.value(row, column.key)).font(.subheadline).monospacedDigit().lineLimit(1)
        }
    }

    /// Every supplied statistic of the row, and the team's games.
    private func expanded(_ row: SportsTableRow, table: SportsLeagueTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(table.columns, id: \.key) { column in
                    SportsReading("\(column.label):", SportsStandings.value(row, column.key))
                }
            }
            if let onTeamSelect, row.kind == "team" {
                Button("Show \(row.abbreviation.flatMap { $0.isEmpty ? nil : $0 } ?? row.name) Games") { onTeamSelect(row) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("sports-standings-show-games")
            }
        }
        .padding(.leading, 12)
        .padding(.bottom, 10)
    }
}
#endif
