import SwiftUI

/// The matchup preview before a game (Expo `SportsPregamePreview`): each side's record and
/// standing, the season comparison, recent form, probable starters and season leaders, and
/// the previous meeting. Season context only; never this game's statistics. Each panel is
/// one stop for the remote, the two sides side by side.
struct SportsPregamePreview: View {
    let page: SportsGamePage
    let pregame: SportsPregame?
    /// Scores hidden: the game's own records and rankings stay out.
    var spoilerSafe = false

    var body: some View {
        if hasContext {
            VStack(alignment: .leading, spacing: 24) {
                SportsSectionHeading(title: String(localized: "Matchup Preview"), note: note)
                SportsColumns {
                    ForEach(page.teams, id: \.id) { standingPanel($0) }
                }
                if let comparisons = pregame?.comparisons, !comparisons.isEmpty { comparisonPanel(comparisons) }
                SportsColumns {
                    ForEach(page.teams, id: \.id) { recentPanel($0) }
                }
                SportsColumns {
                    ForEach(page.teams, id: \.id) { playerPanels($0) }
                }
                if let meeting = pregame?.previousMeeting, let home = page.team(id: meeting.homeTeamId),
                   let away = page.team(id: meeting.awayTeamId) {
                    SportsPanel(String(localized: "Previous Meeting")) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(away.name) \(meeting.awayScore) · \(home.name) \(meeting.homeScore)")
                            Text("\(Self.dateLabel(meeting.date)) · \(String(localized: "Final"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .sportsReadout()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Data

    private var hasContext: Bool {
        let sides = page.teams.contains { team in
            let context = pregame?.team(team.id)
            return !facts(team, context).isEmpty || context?.standingLabel?.isEmpty == false
                || context?.recent.isEmpty == false || context?.leaders.isEmpty == false || context?.probables.isEmpty == false
        }
        return sides || pregame?.comparisons.isEmpty == false || pregame?.previousMeeting != nil
    }

    private var note: String {
        [pregame?.seasonLabel.map { String(localized: "\($0) · Season context") } ?? String(localized: "Team context"),
         pregame?.updatedAt.map { String(localized: "Updated \(Self.dateLabel($0))") },
         page.isStale() ? String(localized: "Updates delayed") : nil]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    /// Record, home and away records, conference record, ranking and the table's figures.
    private func facts(_ team: SportsTeam, _ context: SportsPregameTeam?) -> [SportsStat] {
        let rank = context?.rank ?? (spoilerSafe ? nil : team.displayRank)
        let rows: [(String, String?)] = [
            (String(localized: "Record"), context?.record ?? (spoilerSafe ? nil : team.record)),
            (String(localized: "Home"), context?.homeRecord),
            (String(localized: "Away"), context?.awayRecord),
            (String(localized: "Conference"), context?.conferenceRecord ?? (spoilerSafe ? nil : team.conferenceRecord)),
            (String(localized: "Ranking"), rank.map { "#\($0)" }),
        ] + (context?.standingStats ?? []).map { ($0.label, $0.value) }
        return rows.compactMap { label, value in value.flatMap { $0.isEmpty ? nil : SportsStat(label: label, value: $0) } }
    }

    nonisolated static func dateLabel(_ value: String) -> String {
        SportsGame.date(value)?.formatted(.dateTime.month(.abbreviated).day().year()) ?? ""
    }

    // MARK: Panels

    @ViewBuilder private func standingPanel(_ team: SportsTeam) -> some View {
        let context = pregame?.team(team.id)
        let rows = facts(team, context)
        if !rows.isEmpty || context?.standingLabel?.isEmpty == false {
            SportsPanel(nil) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        SportsTeamLogo(team: team, size: 48)
                        Text(team.name).font(.headline)
                    }
                    if let label = context?.standingLabel, !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 24, alignment: .leading)],
                              alignment: .leading, spacing: 14) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label).font(.caption).foregroundStyle(.secondary)
                                Text(row.value)
                            }
                        }
                    }
                }
                .sportsReadout()
            }
            .focusSection()
        }
    }

    private func comparisonPanel(_ rows: [SportsComparison]) -> some View {
        let (left, right) = (page.teams[0], page.teams[1])
        return SportsPanel(String(localized: "Season Comparison")) {
            VStack(spacing: 10) {
                comparisonRow(left.shortName, String(localized: "Season statistics"), right.shortName).fontWeight(.semibold)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Divider()
                    comparisonRow(page.value(row, for: left), row.label, page.value(row, for: right))
                }
            }
            .sportsReadout()
        }
    }

    private func comparisonRow(_ left: String, _ label: String, _ right: String) -> some View {
        HStack {
            Text(left).frame(maxWidth: .infinity)
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            Text(right).frame(maxWidth: .infinity)
        }
        .monospacedDigit()
    }

    @ViewBuilder private func recentPanel(_ team: SportsTeam) -> some View {
        if let games = pregame?.team(team.id)?.recent, !games.isEmpty {
            SportsPanel(String(localized: "\(team.shortName) · Recent Form"), note: String(localized: "Latest completed games first")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(games) { game in
                        HStack(spacing: 18) {
                            Text(game.result).font(.headline).frame(width: 44)
                                .foregroundStyle(game.result == "W" ? Color.green : .primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text([game.opponent, game.score].compactMap { $0 }.joined(separator: " · ")).lineLimit(1)
                                Text(Self.dateLabel(game.date)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .sportsReadout()
            }
            .focusSection()
        }
    }

    @ViewBuilder private func playerPanels(_ team: SportsTeam) -> some View {
        if let context = pregame?.team(team.id), !(context.probables.isEmpty && context.leaders.isEmpty) {
            VStack(spacing: 24) {
                if !context.probables.isEmpty {
                    playersPanel(String(localized: "\(team.shortName) · Probable Starter"), context.probables)
                }
                if !context.leaders.isEmpty {
                    playersPanel(String(localized: "\(team.shortName) · Season Leaders"), context.leaders)
                }
            }
            .focusSection()
        }
    }

    private func playersPanel(_ title: String, _ players: [SportsPregamePlayer]) -> some View {
        SportsPanel(title) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.label).font(.caption).foregroundStyle(.secondary)
                        Text([player.name, player.value].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    }
                }
            }
            .sportsReadout()
        }
    }
}
