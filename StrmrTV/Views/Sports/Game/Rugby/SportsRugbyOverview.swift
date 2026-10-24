import SwiftUI

/// The Overview of rugby union and rugby league matches (Expo `SportsSportOverview`'s rugby
/// branch): the scoring and discipline timeline and the match comparison beside the
/// substitutions, the lineups and the match information. When the feed has no scoring events the
/// timeline (saying so) moves to the second column. A match not under way opens with the
/// availability notice; a scheduled one ends with the matchup preview.
struct SportsRugbyOverview: View {
    let page: SportsGamePage

    private enum Panel: Hashable { case availability, timeline, stats, substitutions, lineups, info }

    var body: some View {
        let keyEvents = page.detail.plays.contains(where: SportsRugby.isKeyEvent)
        let left = ([.availability] + (keyEvents ? [.timeline] : []) + [.stats]).filter(shows)
        let right = ((keyEvents ? [] : [.timeline]) + [Panel.substitutions, .lineups, .info]).filter(shows)
        VStack(alignment: .leading, spacing: 40) {
            SportsColumns(weights: [1.2, 1]) {
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
        switch panel {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .timeline: return SportsRugbyTimeline.shows(page, substitutions: false)
        case .stats: return page.lifecycle != .scheduled && !page.detail.comparisons.isEmpty
        case .substitutions: return SportsRugbyTimeline.shows(page, substitutions: true)
        case .lineups: return SportsRugbyLineups.shows(page)
        case .info: return !SportsMatchInfo.items(page).isEmpty || SportsMatchInfo.hasNotes(page)
        }
    }

    @ViewBuilder private func panel(_ panel: Panel) -> some View {
        switch panel {
        case .availability: SportsAvailabilityNotice(page: page)
        case .timeline: SportsRugbyTimeline(page: page)
        case .stats:
            SportsTeamComparison(page: page, rows: SportsTeamComparison.priorityRows(page), title: SportsTeamComparison.title(page.kind))
        case .substitutions: SportsRugbyTimeline(page: page, substitutions: true)
        case .lineups: SportsRugbyLineups(page: page)
        case .info: SportsMatchInfo(page: page)
        }
    }
}
