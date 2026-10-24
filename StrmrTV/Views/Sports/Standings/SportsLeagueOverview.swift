import SwiftUI

/// A team competition's details (Expo `SportsLeagueOverview`, wide layout): its standings beside
/// the hub day's games of the league, live first, then upcoming, then results (newest first).
/// A standings row's "Show … Games" narrows the games to that team; Show All Teams undoes it.
struct SportsLeagueOverview: View {
    @ObservedObject var hub: SportsHubStore
    let league: String

    @StateObject private var standings: SportsStandingsModel
    @ObservedObject private var spoilers = SportsSpoilers.shared
    @State private var team: (id: String, name: String)?

    init(hub: SportsHubStore, league: String) {
        self.hub = hub
        self.league = league
        _standings = StateObject(wrappedValue: SportsStandingsModel(league: league))
    }

    var body: some View {
        let all = hub.games.filter { $0.league == league }
        let games = all.filter { team == nil || $0.awayTeam.id == team?.id || $0.homeTeam.id == team?.id }
            .map { game in standings.standings.map { SportsStandings.withRecords(game, $0.groups) } ?? game }
            .sorted(by: Self.fixtureOrder)
        SportsColumns(weights: [1.3, 1]) {
            SportsLeagueStandingsView(model: standings, fixtureTeamIDs: Set(all.flatMap { [$0.awayTeam.id, $0.homeTeam.id] }),
                                      selectedTeamID: team?.id) { team = ($0.id, $0.name) }
                .frame(maxHeight: .infinity, alignment: .top)
                .focusSection()
            VStack(alignment: .leading, spacing: 18) {
                SportsSectionHeading(title: team?.name ?? String(localized: "Games"), note: "\(hub.day.label) · \(hub.leagueName(league))")
                if team != nil {
                    Button("Show All Teams") { team = nil }.accessibilityIdentifier("sports-show-all-teams")
                }
                if games.isEmpty {
                    Text(team != nil ? "No games for this team in the current selection. Choose another day or show all teams."
                         : "No games in this selection. The league table remains available.")
                        .foregroundStyle(.secondary).sportsReadout()
                }
                ForEach(games) { SportsFixtureRow(game: $0, league: hub.leagues[$0.league], spoilers: spoilers.hidden) }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .focusSection()
        }
    }

    /// Live first, then upcoming by start, then results newest first.
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

/// A game of the league (Expo's fixture card): status, each side with its rank, record and score,
/// broadcasts. Select opens the game.
struct SportsFixtureRow: View {
    let game: SportsGame
    let league: SportsLeague?
    let spoilers: Bool

    var body: some View {
        let kind = SportsKind(league: league, game: game)
        NavigationLink(value: SportsGameRef(id: game.id, title: game.displayTitle)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(SportsFormat.statusLine(game, spoilers: spoilers)).font(.caption).lineLimit(1)
                    .foregroundStyle(game.lifecycle == .live ? SportsStatusPill.live : .secondary)
                ForEach(kind.awayFirst ? [game.awayTeam, game.homeTeam] : [game.homeTeam, game.awayTeam], id: \.id) { side($0) }
                if let broadcasts = game.broadcasts, !broadcasts.isEmpty {
                    Text(broadcasts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(SportsReadoutButtonStyle())
        .accessibilityIdentifier("sports-fixture-\(game.id)")
    }

    private func side(_ team: SportsTeam) -> some View {
        HStack(spacing: 16) {
            SportsTeamLogo(team: team, size: 40)
            // Name over record, so neither crowds the other out.
            VStack(alignment: .leading, spacing: 2) {
                Text([spoilers ? nil : team.displayRank.map { "#\($0)" }, team.name].compactMap { $0 }.joined(separator: " "))
                    .font(.callout.weight(.semibold)).lineLimit(1)
                if !spoilers, let record = team.record, !record.isEmpty {
                    Text(record).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if game.lifecycle != .scheduled && !spoilers {
                Text(team.score ?? "–").font(.title3.weight(.bold)).monospacedDigit().lineLimit(1).fixedSize()
                    .frame(minWidth: 80, alignment: .trailing)
            }
        }
    }
}
