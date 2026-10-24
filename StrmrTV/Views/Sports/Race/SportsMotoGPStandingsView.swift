import SwiftUI

/// The MotoGP riders' championship (Expo `SportsMotoGPStandings`): the season's table with
/// points, wins and podiums, notices while it loads or when it's late, and where it comes from.
/// Kept apart from the shown session's results.
struct SportsMotoGPStandingsView: View {
    let standings: SportsMotoGPEnrichment?
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        let riders = standings?.standings ?? []
        VStack(alignment: .leading, spacing: 18) {
            SportsSectionHeading(
                title: [standings?.season.map { String($0) }, String(localized: "MotoGP championship")].compactMap { $0 }
                    .joined(separator: " "),
                note: (standings?.captured == true ? String(localized: "Captured season standings")
                       : String(localized: "Latest season standings"))
                    + " · " + String(localized: "Separate from the selected race's results"))
            if standings == nil && !failed {
                SportsNotice(title: String(localized: "Loading championship"),
                             message: String(localized: "Fetching official rider standings."), loading: true)
            }
            if failed || standings?.stale == true || standings?.unavailable == true {
                SportsNotice(title: riders.isEmpty ? String(localized: "Standings unavailable") : String(localized: "Standings updates delayed"),
                             message: standings?.reason ?? String(localized: "The latest standings could not be reached. Any displayed values are from the last successful update."),
                             retry: retry)
            }
            if !riders.isEmpty {
                SportsPanel(nil) {
                    HStack(spacing: 0) {
                        SportsColumnHeading(String(localized: "Pos")).frame(width: 80)
                        SportsColumnHeading(String(localized: "Rider / Team"))
                        SportsColumnHeading(String(localized: "Points"), alignment: .trailing).frame(width: 140)
                    }
                    ForEach(riders) { row($0) }
                }
            }
            if let standings {
                let checked = SportsRaceFormat.checked(standings.updatedAt.flatMap(SportsRaceEvent.date))
                Text("\(standings.source.isEmpty ? "MotoGP" : standings.source) · \(checked)").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ rider: SportsMotoGPRider) -> some View {
        HStack(spacing: 0) {
            Text(rider.position.map(String.init) ?? "—").font(.title3.weight(.bold))
                .foregroundStyle(rider.position == 1 ? SportsStatusPill.accent : .primary)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                (Text(rider.name).fontWeight(.semibold) + Text(rider.number.map { "  #\($0)" } ?? "").foregroundStyle(.secondary))
                    .font(.callout).lineLimit(1)
                let about = [SportsRaceDriver.filled(rider.team),
                             rider.wins.map { $0 == 1 ? String(localized: "1 win") : String(localized: "\($0) wins") },
                             rider.podiums.map { $0 == 1 ? String(localized: "1 podium") : String(localized: "\($0) podiums") }]
                    .compactMap { $0 }
                if !about.isEmpty { Text(about.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(rider.pointsText).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(SportsStatusPill.accent)
                .frame(width: 140, alignment: .trailing)
        }
        .sportsReadout()
    }
}
