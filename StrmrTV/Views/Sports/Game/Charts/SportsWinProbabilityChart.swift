import Charts
import SwiftUI

/// ESPN's win probability over the game in Swift Charts (Expo `SportsWinProbability`): each side's
/// chance in its colour (home, and away as the rest), a dashed 50% rule, the periods along the
/// bottom and the latest estimate marked and labelled. One stop for the remote.
struct SportsWinProbabilityChart: View {
    let page: SportsGamePage
    let series: SportsWinProbabilitySeries

    var body: some View {
        let game = page.game
        let colors = SportsTeamColors.chartPair(away: game.awayTeam, home: game.homeTeam)
        let home = Color(hex: colors.home) ?? .yellow, away = Color(hex: colors.away) ?? .cyan
        let latest = series.latest
        SportsPanel(String(localized: "Win Probability")) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 28) {
                    Text("\(game.homeTeam.shortName) \(Self.percent(latest.home))").foregroundStyle(home)
                    Text("\(game.awayTeam.shortName) \(Self.percent(1 - latest.home))").foregroundStyle(away)
                }
                .font(.headline.monospacedDigit())
                chart(home: home, away: away)
                    .frame(height: 260)
                Text("ESPN model · \([latest.periodLabel, latest.clock].filter { !$0.isEmpty }.joined(separator: " ")) · Latest available estimate")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .sportsReadout()
            .accessibilityLabel(String(localized: "ESPN win probability. \(game.homeTeam.name) \(Self.percent(latest.home)). \(game.awayTeam.name) \(Self.percent(1 - latest.home))."))
        }
    }

    private func chart(home: Color, away: Color) -> some View {
        let latest = series.latest
        return Chart {
            RuleMark(y: .value("Even", 0.5))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Time", point.elapsed), y: .value("Chance", 1 - point.home), series: .value("Side", "away"))
                    .foregroundStyle(away)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", point.elapsed), y: .value("Chance", point.home), series: .value("Side", "home"))
                    .foregroundStyle(home)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            PointMark(x: .value("Time", latest.elapsed), y: .value("Chance", latest.home))
                .foregroundStyle(home)
                .symbolSize(160)
                .annotation(position: latest.home > 0.75 ? .bottom : .top, alignment: .trailing, spacing: 6) {
                    Text(Self.percent(latest.home)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(home)
                }
        }
        .chartYScale(domain: 0...1)
        .chartXScale(domain: 0...series.duration)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.15))
                AxisValueLabel { Text(Self.percent(value.as(Double.self) ?? 0, digits: 0)).font(.caption) }
            }
        }
        .chartXAxis { SportsChartPeriodAxis.marks(series.periods) }
        .accessibilityHidden(true)
    }

    /// "99.8%".
    static func percent(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.percent.precision(.fractionLength(digits)))
    }
}

/// The period lines and short labels along a chart's bottom ("Q1", "H2", "OT1").
enum SportsChartPeriodAxis {
    static func marks(_ periods: [SportsChartPeriod]) -> some AxisContent {
        AxisMarks(values: periods.map(\.start)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [4, 5])).foregroundStyle(Color.white.opacity(0.2))
            AxisValueLabel(anchor: .topLeading) {
                let start = value.as(Double.self)
                Text(periods.first { $0.start == start }?.label ?? "").font(.caption)
            }
        }
    }
}
