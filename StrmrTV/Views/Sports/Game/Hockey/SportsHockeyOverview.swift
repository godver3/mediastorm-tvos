import SwiftUI

/// The Overview of NHL games (Expo `SportsSportOverview`'s ice-hockey branch): the latest event or
/// a final's scoring highlights and the match stats (with the reported strength while live) beside
/// the goals by period, the shot-attempt map, the goalies and the game's facts. A game not under
/// way opens with the availability notice; a scheduled one ends with the matchup preview.
struct SportsHockeyOverview: View {
    let page: SportsGamePage

    private enum Panel: Hashable { case availability, timeline, stats, periods, shots, goalies, info }

    var body: some View {
        let left = [Panel.availability, .timeline, .stats].filter(shows)
        let right = [Panel.periods, .shots, .goalies, .info].filter(shows)
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

    /// "Reported strength · Boston Bruins power play · 1:18" while live ("Last reported…" when old).
    private var strength: String? {
        guard let strength = page.game.liveHockeySituation?.strength, !strength.isEmpty else { return nil }
        return page.isStale() ? String(localized: "Last reported strength · \(strength)") : String(localized: "Reported strength · \(strength)")
    }

    private func shows(_ panel: Panel) -> Bool {
        let started = page.lifecycle != .scheduled
        switch panel {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .timeline: return !SportsHockeyTimeline.events(page).isEmpty
        case .stats: return started && (!page.detail.comparisons.isEmpty || strength != nil)
        case .periods: return started && !page.detail.periods.isEmpty
        case .shots: return !SportsHockeyShotMap.shots(page).isEmpty
        case .goalies: return !SportsResultPerformers.entries(page).isEmpty
        case .info: return !SportsMatchInfo.items(page).isEmpty || SportsMatchInfo.hasNotes(page)
        }
    }

    @ViewBuilder private func panel(_ panel: Panel) -> some View {
        switch panel {
        case .availability: SportsAvailabilityNotice(page: page)
        case .timeline: SportsHockeyTimeline(page: page)
        case .stats:
            SportsTeamComparison(page: page, rows: SportsTeamComparison.priorityRows(page),
                                 title: SportsTeamComparison.title(page.kind), note: strength)
        case .periods: SportsPeriodBreakdown(page: page)
        case .shots: SportsHockeyShotMap(page: page)
        case .goalies: SportsResultPerformers(page: page)
        case .info: SportsMatchInfo(page: page)
        }
    }
}
