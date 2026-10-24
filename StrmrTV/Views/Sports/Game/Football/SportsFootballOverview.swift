import SwiftUI

/// The Overview of NFL and college football games (Expo `FootballOverview`): the possession field
/// and the recent or scoring plays beside the team comparison and the scoring by quarter, then the
/// latest drives beside the game leaders and the game's facts. A game that isn't under way opens
/// with the availability notice; a scheduled one carries the matchup preview before the facts.
/// The field keeps a column's width: with nothing beside it, it takes the right-hand column.
struct SportsFootballOverview: View {
    let page: SportsGamePage

    private enum Panel: Hashable { case availability, field, plays, comparison, quarters, drives, leaders, info }

    var body: some View {
        let possession = SportsFootballPossession(page: page)
        let detail = page.detail
        let right = [Panel.comparison, .quarters].filter(shows)
        let field: [Panel] = possession == nil ? [] : [.field]
        let left = [Panel.availability].filter(shows) + (right.isEmpty ? [] : field) + [Panel.plays].filter(shows)
        let lower = [[Panel.drives].filter(shows), [Panel.leaders, .info].filter(shows)]
        VStack(alignment: .leading, spacing: 40) {
            SportsColumns(weights: [1.1, 1]) {
                if !left.isEmpty { column(left, possession: possession) }
                if !right.isEmpty || !field.isEmpty { column(right.isEmpty ? field : right, possession: possession) }
            }
            if page.lifecycle == .scheduled {
                SportsPregamePreview(page: page, pregame: detail.pregame)
            } else if lower.contains(where: { !$0.isEmpty }) {
                Label("More game details below", systemImage: "chevron.down")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            SportsColumns(weights: [1.5, 1]) {
                ForEach(lower.filter { !$0.isEmpty }, id: \.self) { column($0, possession: possession) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ panels: [Panel], possession: SportsFootballPossession?) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(panels, id: \.self) { panel($0, possession: possession) }
        }
        .focusSection()
    }

    private func shows(_ panel: Panel) -> Bool {
        let detail = page.detail
        switch panel {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .field: return SportsFootballPossession(page: page) != nil
        case .plays: return !detail.plays.isEmpty
        case .comparison: return !detail.comparisons.isEmpty
        case .quarters: return !detail.periods.isEmpty
        case .drives: return SportsRecentDrives.shows(page)
        case .leaders: return !detail.leaders.isEmpty
        case .info: return !SportsMatchInfo.items(page).isEmpty || SportsMatchInfo.hasNotes(page)
        }
    }

    @ViewBuilder private func panel(_ panel: Panel, possession: SportsFootballPossession?) -> some View {
        switch panel {
        case .availability: SportsAvailabilityNotice(page: page)
        case .field:
            if let possession {
                SportsFootballPossessionField(page: page, possession: possession).frame(maxWidth: 1000, alignment: .leading)
            }
        case .plays: SportsKeyPlays(page: page, teamMarks: true)
        case .comparison:
            SportsTeamComparison(page: page, rows: Array(page.detail.comparisons.prefix(5)),
                                 title: String(localized: "Team Comparison"), style: .share)
        case .quarters: SportsPeriodBreakdown(page: page)
        case .drives: SportsRecentDrives(page: page, possession: possession)
        case .leaders: SportsGameLeaders(page: page)
        case .info: SportsMatchInfo(page: page, title: String(localized: "Game Information"))
        }
    }
}
