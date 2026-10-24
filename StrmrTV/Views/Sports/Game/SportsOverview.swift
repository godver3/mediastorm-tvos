import SwiftUI

/// The generic panels an Overview is built from (Expo's shared detail panels), each shown
/// only when the feed sent its data. A sport's own Overview can reuse them with its panels
/// (`SportsOverviewLayout`).
enum SportsOverviewPanel: Hashable {
    /// What the feed hasn't sent, or that play is held up (Expo `SportsMatchAvailability`).
    case availability
    /// Points per period (Expo `SportsPeriodBreakdown`).
    case periods
    /// The sport's key team statistics side by side (Expo `SportsPriorityStats` / `StatsPanel`).
    case teamStats
    /// The latest or scoring plays (Expo `RecentDetailPlays`).
    case keyPlays
    /// The feed's game leaders (Expo `CompactDetailLeaders`).
    case leaders
    /// Baseball's top batter and pitcher, hockey's goalies (Expo `SportsResultPerformers`).
    case performers
    /// Venue, broadcast, format, records and coverage (Expo `EventInfo`, `SportsTeamContext`).
    case matchInfo

    func shows(_ page: SportsGamePage) -> Bool {
        let detail = page.detail
        let started = page.lifecycle != .scheduled
        switch self {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .periods: return started && !detail.periods.isEmpty
        case .teamStats: return started && !detail.comparisons.isEmpty
        case .keyPlays: return !detail.plays.isEmpty
        case .leaders: return !detail.leaders.isEmpty
        case .performers: return !SportsResultPerformers.entries(page).isEmpty
        case .matchInfo: return !SportsMatchInfo.items(page).isEmpty || SportsMatchInfo.hasNotes(page)
        }
    }

    @ViewBuilder func view(_ page: SportsGamePage) -> some View {
        switch self {
        case .availability: SportsAvailabilityNotice(page: page)
        case .periods: SportsPeriodBreakdown(page: page)
        case .teamStats: SportsTeamComparison(page: page, rows: SportsTeamComparison.priorityRows(page), title: SportsTeamComparison.title(page.kind))
        case .keyPlays: SportsKeyPlays(page: page)
        case .leaders: SportsGameLeaders(page: page)
        case .performers: SportsResultPerformers(page: page)
        case .matchInfo: SportsMatchInfo(page: page)
        }
    }
}

/// An Overview in two columns (Expo `SportsOverviewLayout`: primary 1.2, secondary 1; one
/// column when the other has nothing), then the matchup preview before the start. Each
/// column is a focus section, so left and right move between them.
struct SportsOverviewLayout: View {
    let page: SportsGamePage
    let primary: [SportsOverviewPanel]
    let secondary: [SportsOverviewPanel]

    var body: some View {
        let left = primary.filter { $0.shows(page) }
        let right = secondary.filter { $0.shows(page) }
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

    private func column(_ panels: [SportsOverviewPanel]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(panels, id: \.self) { $0.view(page) }
        }
        .focusSection()
    }
}

/// The Overview of every sport without its own yet (Expo `SportsSportOverview`'s default and
/// the shared panels of `SportsGameDetailTV`): availability, line score, team stats and key
/// plays beside the leaders, standout performers and match information.
struct SportsGenericOverview: View {
    let page: SportsGamePage

    static let primary: [SportsOverviewPanel] = [.availability, .periods, .teamStats, .keyPlays]
    static let secondary: [SportsOverviewPanel] = [.leaders, .performers, .matchInfo]

    var body: some View {
        SportsOverviewLayout(page: page, primary: Self.primary, secondary: Self.secondary)
    }
}
