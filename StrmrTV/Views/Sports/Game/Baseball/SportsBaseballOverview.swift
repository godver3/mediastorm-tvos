import SwiftUI

/// The Overview of MLB games (Expo `SportsBaseballOverview`): while live, the at-bat (or why there
/// is none); the line score and a final's standout batter and pitcher per side; beside them the
/// recent or scoring plays, the game leaders, the team comparison, and while an at-bat is under
/// way a note that pitch locations aren't drawn. A game not under way opens with the
/// availability notice; a scheduled one ends with the matchup preview.
struct SportsBaseballOverview: View {
    let page: SportsGamePage

    private enum Panel: Hashable { case availability, atBat, lineScore, performers, plays, leaders, comparison, pitches }

    var body: some View {
        let state = SportsBaseballState(game: page.game)
        let left = [Panel.availability, .atBat, .lineScore, .performers].filter { shows($0, state: state) }
        let right = [Panel.plays, .leaders, .comparison, .pitches].filter { shows($0, state: state) }
        VStack(alignment: .leading, spacing: 40) {
            SportsColumns(weights: [1.1, 1]) {
                if !left.isEmpty { column(left, state: state) }
                if !right.isEmpty { column(right, state: state) }
            }
            if page.lifecycle == .scheduled {
                SportsPregamePreview(page: page, pregame: page.detail.pregame)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ panels: [Panel], state: SportsBaseballState) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(panels, id: \.self) { panel($0, state: state) }
        }
        .focusSection()
    }

    private func shows(_ panel: Panel, state: SportsBaseballState) -> Bool {
        let detail = page.detail
        let started = page.lifecycle != .scheduled
        switch panel {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .atBat: return page.lifecycle == .live
        case .lineScore: return started && !detail.periods.isEmpty
        case .performers: return !SportsResultPerformers.entries(page).isEmpty
        case .plays: return !detail.plays.isEmpty
        case .leaders: return !detail.leaders.isEmpty
        case .comparison: return started && !detail.comparisons.isEmpty
        case .pitches: return state.active
        }
    }

    @ViewBuilder private func panel(_ panel: Panel, state: SportsBaseballState) -> some View {
        switch panel {
        case .availability: SportsAvailabilityNotice(page: page)
        case .atBat: SportsBaseballAtBat(page: page, state: state)
        case .lineScore: SportsBaseballLineScoreView(page: page)
        case .performers: SportsResultPerformers(page: page)
        case .plays: SportsKeyPlays(page: page)
        case .leaders: SportsGameLeaders(page: page)
        case .comparison:
            SportsTeamComparison(page: page, rows: SportsTeamComparison.priorityRows(page), title: String(localized: "Team Comparison"))
        case .pitches:
            Text(page.detail.capabilities.plays
                 ? String(localized: "Pitch locations are not supplied in this view. Reported pitches appear in Play-by-Play.")
                 : String(localized: "Pitch locations are not supplied in this view."))
                .font(.caption).foregroundStyle(.secondary).sportsReadout()
        }
    }
}

/// MLB's line score (Expo `SportsPeriodBreakdown` for MLB, "Line score"): each side's runs by
/// inning, at least nine, the inning being played in the accent colour, then runs, hits and
/// errors. One stop for the remote; columns narrow to fit extra innings.
struct SportsBaseballLineScoreView: View {
    let page: SportsGamePage

    var body: some View {
        let score = SportsBaseballLineScore(page: page)
        SportsPanel(String(localized: "Line Score")) {
            ViewThatFits(in: .horizontal) {
                table(score, cell: 58)
                table(score, cell: 46)
                table(score, cell: 36)
            }
            .sportsReadout()
            .accessibilityLabel(spoken(score))
        }
    }

    private func table(_ score: SportsBaseballLineScore, cell: CGFloat) -> some View {
        Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 12) {
            GridRow {
                Text("TEAM").gridColumnAlignment(.leading).frame(minWidth: 120, alignment: .leading)
                ForEach(score.innings, id: \.number) { inning in
                    Text("\(inning.number)").frame(width: cell)
                        .foregroundStyle(inning.number == score.current ? Color.accentColor : .secondary)
                }
                Divider().frame(height: 24)
                ForEach(score.totals, id: \.label) { Text($0.label).frame(width: cell + 8) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(page.teams, id: \.id) { team in
                let home = team.id == page.game.homeTeam.id
                GridRow {
                    HStack(spacing: 12) {
                        SportsTeamLogo(team: team, size: 36)
                        Text(team.shortName).fontWeight(.semibold).lineLimit(1)
                    }
                    .gridColumnAlignment(.leading)
                    ForEach(score.innings, id: \.number) { Text(home ? $0.home : $0.away).frame(width: cell) }
                    Divider().frame(height: 30)
                    ForEach(score.totals, id: \.label) { total in
                        Text(home ? total.home : total.away).fontWeight(.bold).frame(width: cell + 8)
                            .foregroundStyle(total.label == "R" ? Color.accentColor : .primary)
                    }
                }
            }
        }
        .monospacedDigit()
        .fixedSize()
    }

    private func spoken(_ score: SportsBaseballLineScore) -> String {
        page.teams.map { team in
            let home = team.id == page.game.homeTeam.id
            let runs = score.innings.map { home ? $0.home : $0.away }.joined(separator: ", ")
            let totals = score.totals.map { "\($0.label) \(home ? $0.home : $0.away)" }.joined(separator: ", ")
            return "\(team.name): \(runs). \(totals)"
        }.joined(separator: ". ")
    }
}
