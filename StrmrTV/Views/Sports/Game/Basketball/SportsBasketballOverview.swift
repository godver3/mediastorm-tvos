import SwiftUI

/// The Overview of NBA, WNBA and college basketball games (Expo `SportsGameDetailTV`'s basketball
/// columns on TV): the shot chart, each side's top scorer and the lead history beside the key team
/// statistics, the win probability, the game leaders (when the box score has no points), the
/// scoring by period, the recent or scoring plays and the game's facts. A game not under way opens
/// with the availability notice; a scheduled one ends with the matchup preview. Each column is a
/// focus section.
struct SportsBasketballOverview: View {
    let page: SportsGamePage

    private enum Panel: Hashable { case availability, court, scorers, lead, stats, winProbability, leaders, periods, plays, info }

    var body: some View {
        let left = [Panel.availability, .court, .scorers, .lead].filter(shows)
        let right = [Panel.stats, .winProbability, .leaders, .periods, .plays, .info].filter(shows)
        VStack(alignment: .leading, spacing: 40) {
            SportsColumns(weights: [1, 1]) {
                if !left.isEmpty { column(left) }
                if !right.isEmpty { column(right) }
            }
            if page.lifecycle == .scheduled {
                SportsPregamePreview(page: page, pregame: page.detail.pregame)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ panels: [Panel]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(panels, id: \.self) { panel($0) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .focusSection()
    }

    private func shows(_ panel: Panel) -> Bool {
        let detail = page.detail
        let started = page.lifecycle != .scheduled
        switch panel {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .court: return SportsBasketballCourtCard.shows(page)
        case .scorers: return started && !SportsBasketballScoringLeaders.leaders(page).isEmpty
        case .lead: return SportsLeadSeries(page: page) != nil
        case .stats: return started && !SportsBasketballTeamStats.rows(detail.comparisons).isEmpty
        case .winProbability: return SportsWinProbabilitySeries(page: page) != nil
        case .leaders: return !detail.leaders.isEmpty && !shows(.scorers)
        case .periods: return started && !detail.periods.isEmpty
        case .plays: return !detail.plays.isEmpty
        case .info: return !SportsMatchInfo.items(page).isEmpty || SportsMatchInfo.hasNotes(page)
        }
    }

    @ViewBuilder private func panel(_ panel: Panel) -> some View {
        switch panel {
        case .availability: SportsAvailabilityNotice(page: page)
        case .court: SportsBasketballCourtCard(page: page)
        case .scorers: SportsBasketballScoringLeaders(page: page)
        case .lead: if let series = SportsLeadSeries(page: page) { SportsLeadHistoryChart(page: page, series: series) }
        case .stats: SportsBasketballTeamStats(page: page)
        case .winProbability:
            if let series = SportsWinProbabilitySeries(page: page) { SportsWinProbabilityChart(page: page, series: series) }
        case .leaders: SportsGameLeaders(page: page)
        case .periods: SportsPeriodBreakdown(page: page)
        case .plays: SportsKeyPlays(page: page)
        case .info: SportsMatchInfo(page: page, title: String(localized: "Game Information"))
        }
    }
}
