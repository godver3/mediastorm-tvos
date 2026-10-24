import SwiftUI

/// A tab of a game's page, in the Expo TV page's order (`SportsGameDetailTV`): Overview, the
/// sport's own tabs (Drives for NFL and college football, Lineups for soccer), Box Score or
/// Match Stats, Play-by-Play or Commentary, Standings.
enum SportsGameTab: String, CaseIterable, Identifiable {
    case overview, drives, lineups, stats, plays, standings

    var id: String { rawValue }

    func label(_ kind: SportsKind) -> String {
        switch self {
        case .overview: String(localized: "Overview")
        case .drives: String(localized: "Drives")
        case .lineups: String(localized: "Lineups")
        case .stats: kind == .soccer ? String(localized: "Match Stats") : String(localized: "Box Score")
        case .plays: kind == .soccer ? String(localized: "Commentary") : String(localized: "Play-by-Play")
        case .standings: String(localized: "Standings")
        }
    }

    /// Whether the feed can fill this tab (Expo `availableTab`): drives and lineups when sent,
    /// stats and plays by the detail's capabilities (no stats tab for golf tournaments or
    /// cricket, whose Overview carries their scorecards), standings when a table came along.
    func isAvailable(for page: SportsGamePage) -> Bool {
        let detail = page.detail
        switch self {
        case .overview: return true
        case .drives: return page.isFootballLeague && !detail.footballDrives.isEmpty
        case .lineups: return page.kind == .soccer && !detail.lineups.isEmpty
        case .stats: return detail.capabilities.stats && !page.isIndividualGolf && page.kind != .cricket
        case .plays: return detail.capabilities.plays
        case .standings: return !detail.standings.isEmpty
        }
    }

    /// The page's tabs. None with scores hidden: the page then shows only what was known
    /// before the start (Expo hides the tab rail while stats are suppressed).
    static func available(for page: SportsGamePage, spoilers: Bool) -> [SportsGameTab] {
        spoilers ? [] : allCases.filter { $0.isAvailable(for: page) }
    }

    /// The tab to show: the one picked while it has data, else the Overview. The pick is
    /// kept, so a tab that empties for a refresh comes back with its data.
    static func shown(_ picked: SportsGameTab, in tabs: [SportsGameTab]) -> SportsGameTab {
        tabs.contains(picked) ? picked : .overview
    }
}

/// What holds focus in a game page's controls.
enum SportsGameFocus: Hashable {
    case watch, spoilers
    case tab(SportsGameTab)
}

/// The page's tabs as a row of chips (the hub's filters): Select shows a tab, and moving up
/// from the panels lands on the shown one.
struct SportsGameTabRow: View {
    let tabs: [SportsGameTab]
    let kind: SportsKind
    let shown: SportsGameTab
    let focus: FocusState<SportsGameFocus?>.Binding
    let select: (SportsGameTab) -> Void

    var body: some View {
        HStack(spacing: 18) {
            ForEach(tabs) { tab in
                Button(tab.label(kind)) { select(tab) }
                    .buttonStyle(FilterChipStyle(selected: tab == shown))
                    .focused(focus, equals: .tab(tab))
                    .accessibilityIdentifier("sports-tab-\(tab.rawValue)")
            }
        }
        .font(.callout)
        .lineLimit(1)
        .sportsChipRow(alignment: .center)
        .defaultFocus(focus, .tab(shown), priority: .userInitiated)
    }
}
