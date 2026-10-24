import Charts
import SwiftUI

/// The lead over the game in Swift Charts (Expo `SportsLeadHistory`): the margin by elapsed time,
/// the away side's lead above zero filled in its colour, the home side's below in its own, the
/// periods along the bottom and the latest margin marked. One stop for the remote.
struct SportsLeadHistoryChart: View {
    let page: SportsGamePage
    let series: SportsLeadSeries

    var body: some View {
        let game = page.game
        let colors = SportsTeamColors.chartPair(away: game.awayTeam, home: game.homeTeam)
        let away = Color(hex: colors.away) ?? .cyan, home = Color(hex: colors.home) ?? .yellow
        SportsPanel(String(localized: "Lead History"),
                    note: String(localized: "\(game.awayTeam.shortName) leads above zero · \(game.homeTeam.shortName) below")) {
            VStack(alignment: .leading, spacing: 14) {
                chart(away: away, home: home).frame(height: 280)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            .sportsReadout()
            .accessibilityLabel(String(localized: "Lead history. \(game.awayTeam.name) above zero, \(game.homeTeam.name) below zero. Score \(game.awayTeam.score ?? "") to \(game.homeTeam.score ?? "")."))
        }
    }

    /// "PHI +8 · Final · Curve connects reported scores".
    private var summary: String {
        let game = page.game
        let lead = series.latest
        let margin = lead == 0 ? String(localized: "Tied")
            : "\(lead > 0 ? game.awayTeam.shortName : game.homeTeam.shortName) +\(Int(abs(lead)))"
        let state = page.lifecycle == .final ? String(localized: "Final") : String(localized: "Latest score")
        return [margin, state, String(localized: "Curve connects reported scores")].joined(separator: " · ")
    }

    private func chart(away: Color, home: Color) -> some View {
        let extent = series.extent
        let last = series.points[series.points.count - 1]
        let curve = series.crossings
        return Chart {
            ForEach(Array(curve.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("Time", point.elapsed), yStart: .value("Even", 0), yEnd: .value("Lead", max(point.lead, 0)),
                         series: .value("Side", "away"))
                    .foregroundStyle(away.opacity(0.2))
                AreaMark(x: .value("Time", point.elapsed), yStart: .value("Even", 0), yEnd: .value("Lead", min(point.lead, 0)),
                         series: .value("Side", "home"))
                    .foregroundStyle(home.opacity(0.2))
            }
            ForEach(Array(series.runs.enumerated()), id: \.offset) { index, run in
                ForEach(Array(run.points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Time", point.elapsed), y: .value("Lead", point.lead), series: .value("Run", index))
                        .foregroundStyle(run.away.map { $0 ? away : home } ?? Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            RuleMark(y: .value("Tie", 0)).foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1.5))
            PointMark(x: .value("Time", last.elapsed), y: .value("Lead", last.lead))
                .foregroundStyle(.white)
                .symbolSize(140)
        }
        .chartYScale(domain: -extent...extent)
        .chartXScale(domain: 0...series.duration)
        .chartYAxis {
            AxisMarks(position: .leading, values: [-extent, -extent / 2, 0, extent / 2, extent]) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.15))
                AxisValueLabel {
                    let lead = value.as(Double.self) ?? 0
                    Text(lead == 0 ? String(localized: "Tie") : "\(Int(abs(lead)))").font(.caption)
                }
            }
        }
        .chartXAxis { SportsChartPeriodAxis.marks(series.periods) }
        .accessibilityHidden(true)
    }
}
