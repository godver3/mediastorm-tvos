import SwiftUI

/// The hub's Competition Details (Expo `SportsHubTV`'s details view) as a page: the cycling race
/// calendar (`SportsCyclingCalendar`), the race weekends and championships
/// (`SportsRacingCalendar`, open on the chosen series), or a team competition's standings and
/// games (`SportsLeagueOverview`). Menu returns to the hub.
struct SportsCompetitionView: View {
    let route: SportsCompetitionRoute
    @ObservedObject var hub: SportsHubStore

    var body: some View {
        let chosen = hub.leagues[route.league]
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 36) {
                if route.sport == SportsCycling.sport {
                    SportsCyclingCalendar(hub: hub)
                } else if route.sport == SportsHubFilters.motorsport || chosen?.isRacing == true {
                    SportsRacingCalendar(hub: hub, initialSeries: chosen?.isRacing == true ? route.league : nil)
                } else {
                    SportsBrowseHeading(
                        eyebrow: String(localized: "COMPETITION DETAILS"), title: hub.leagueName(route.league),
                        description: String(localized: "Season standings and \(hub.day.label.lowercased())'s games. Select a game to open it."))
                    SportsLeagueOverview(hub: hub, league: route.league)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CardGridLayout.inset)
            .padding(.top, 20)
            .padding(.bottom, 80)
        }
        // Below the menu's tab pill and clipped there, so headings scroll away under nothing.
        .padding(.top, 70)
    }
}
