import SwiftUI

/// Points per period for both sides with the totals (Expo `SportsPeriodBreakdown`): goals by
/// period for hockey, points by set for volleyball, innings for baseball. One stop for the
/// remote; columns narrow to fit long games (extra innings, overtimes).
struct SportsPeriodBreakdown: View {
    let page: SportsGamePage

    var body: some View {
        let periods = page.detail.periods
        SportsPanel(title) {
            ViewThatFits(in: .horizontal) {
                table(periods, cell: 84)
                table(periods, cell: 64)
                table(periods, cell: 50)
            }
            .sportsReadout()
        }
    }

    private var title: String {
        switch page.kind {
        case .hockey: String(localized: "Goals by Period")
        case .volleyball: String(localized: "Points by Set")
        case .baseball, .softball: String(localized: "Innings")
        case .tennis: String(localized: "Sets")
        case .football: String(localized: "Scoring by Quarter")
        default: String(localized: "Scoring by Period")
        }
    }

    private func table(_ periods: [SportsPeriodScore], cell: CGFloat) -> some View {
        Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 12) {
            GridRow {
                Text("TEAM").gridColumnAlignment(.leading).frame(minWidth: 130, alignment: .leading)
                ForEach(Array(periods.enumerated()), id: \.offset) { _, period in
                    Text(period.label).lineLimit(1).frame(width: cell)
                }
                Text("TOTAL").frame(width: 110)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(page.teams, id: \.id) { team in
                GridRow {
                    HStack(spacing: 12) {
                        SportsTeamLogo(team: team, size: 36)
                        Text(team.shortName).fontWeight(.semibold).lineLimit(1)
                    }
                    .gridColumnAlignment(.leading)
                    ForEach(Array(periods.enumerated()), id: \.offset) { _, period in
                        Text(score(period, team)).frame(width: cell)
                    }
                    Text(team.score ?? "–").fontWeight(.bold).frame(width: 110)
                }
            }
        }
        .monospacedDigit()
        .fixedSize()
    }

    private func score(_ period: SportsPeriodScore, _ team: SportsTeam) -> String {
        let value = team.id == page.game.homeTeam.id ? period.home : period.away
        return value.isEmpty ? "–" : value
    }
}
