import SwiftUI

/// The shown tab's panels: the one place each tab, and each sport's Overview, is chosen.
/// A sport's bespoke views plug in here: an Overview case in `overview`, or a sport-specific
/// tab view in the tab switch (the drives explorer for `.drives`, the pitch for `.lineups`).
struct SportsGameContent: View {
    let page: SportsGamePage
    let tab: SportsGameTab
    /// A player line for the Box Score to open on.
    var playerTarget: SportsPlayerTarget?

    var body: some View {
        switch tab {
        case .overview: Self.overview(page)
        case .drives: SportsDrivesPanel(page: page)
        case .lineups: SportsLineupsPanel(page: page)
        case .stats: SportsBoxScore(page: page, target: playerTarget)
        case .plays: SportsPlayByPlay(page: page)
        case .standings: SportsStandingsPanel(page: page)
        }
    }

    /// A sport's Overview (Expo `SportsSportOverview`, and the football, baseball and
    /// basketball overviews of `SportsGameDetailTV`): golf, cricket, combat, tennis, soccer and
    /// rugby have their own; the rest use the generic panels.
    @ViewBuilder static func overview(_ page: SportsGamePage) -> some View {
        if page.isFootballLeague {
            SportsFootballOverview(page: page)
        } else if page.game.league == "mlb" {
            SportsBaseballOverview(page: page)
        } else if page.kind == .basketball {
            SportsBasketballOverview(page: page)
        } else if page.game.league == "nhl" {
            SportsHockeyOverview(page: page)
        } else if page.isIndividualGolf {
            SportsGolfOverview(page: page)
        } else {
            switch page.kind {
            case .tennis: SportsTennisOverview(page: page)
            case .cricket: SportsCricketOverview(page: page)
            case .mma, .boxing: SportsCombatOverview(page: page)
            case .soccer: SportsSoccerOverview(page: page)
            case .rugbyUnion, .rugbyLeague: SportsRugbyOverview(page: page)
            default: SportsGenericOverview(page: page)
            }
        }
    }
}
