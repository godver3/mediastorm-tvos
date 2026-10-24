import SwiftUI

/// Team statistics side by side (Expo `StatsPanel` and `SportsPriorityStats`): each side's
/// figure around the statistic's name, with bars in the team colours when both are plain
/// numbers. The Overview shows the sport's six key rows; the Box Score tab shows them all.
/// American football splits one bar by each side's share (Expo `FootballComparison`).
struct SportsTeamComparison: View {
    let page: SportsGamePage
    let rows: [SportsComparison]
    let title: String
    var style: Style = .centre
    /// A line under the title (hockey's reported strength while live).
    var note: String?

    enum Style {
        /// Two bars growing out from the centre, each scaled to the larger figure.
        case centre
        /// One bar split by each side's share of the total.
        case share
    }

    var body: some View {
        let teams = page.teams
        let colors = teams.map { SportsTeamColors.color($0, in: page.game) }
        SportsPanel(title, note: note) {
            HStack(spacing: 12) {
                SportsTeamLogo(team: teams[0], size: 40)
                Text(teams[0].shortName)
                Spacer()
                Text(teams[1].shortName)
                SportsTeamLogo(team: teams[1], size: 40)
            }
            .fontWeight(.semibold)
            .padding(.bottom, 4)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let values = teams.map { display(page.value(row, for: $0), label: row.label) }
                VStack(spacing: 8) {
                    // Expo's 1 : 2 : 1 row.
                    SportsColumns(weights: [1, 2, 1], spacing: 12) {
                        Text(values[0]).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Text(values[1]).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if let numbers = Self.numbers(values[0], values[1]) {
                        if style == .share { share(numbers, colors: colors) } else { bars(numbers, colors: colors) }
                    }
                }
                .monospacedDigit()
                .sportsReadout()
            }
        }
    }

    private func bars(_ numbers: (Double, Double), colors: [Color]) -> some View {
        let top = max(numbers.0, numbers.1)
        return HStack(spacing: 14) {
            bar(top > 0 ? numbers.0 / top : 0, color: colors[0], alignment: .trailing)
            bar(top > 0 ? numbers.1 / top : 0, color: colors[1], alignment: .leading)
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func share(_ numbers: (Double, Double), colors: [Color]) -> some View {
        let total = numbers.0 + numbers.1
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(colors[0]).frame(width: total > 0 ? proxy.size.width * numbers.0 / total : 0)
                Rectangle().fill(colors[1]).frame(width: total > 0 ? proxy.size.width * numbers.1 / total : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func bar(_ share: Double, color: Color, alignment: Alignment) -> some View {
        Capsule().fill(Color.white.opacity(0.1))
            .overlay(alignment: alignment) {
                GeometryReader { proxy in
                    Capsule().fill(color).frame(width: proxy.size.width * share)
                        .frame(maxWidth: .infinity, alignment: alignment)
                }
            }
    }

    // MARK: Rules

    /// Both figures as numbers ("12", "45.5", "38%"), else nil: records, times and ratios get
    /// no bars.
    nonisolated static func numbers(_ left: String, _ right: String) -> (Double, Double)? {
        func number(_ text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard SportsFormat.matches(#"^\d+(?:\.\d+)?%?$"#, trimmed) else { return nil }
            return Double(trimmed.replacingOccurrences(of: "%", with: ""))
        }
        guard let a = number(left), let b = number(right) else { return nil }
        return (a, b)
    }

    /// Rugby possession and territory, and soccer accuracy, come as fractions: shown as percent.
    private func display(_ value: String, label: String) -> String {
        let fraction = (page.kind.isRugby && SportsFormat.matches("possession|territory", label))
            || (page.kind == .soccer && SportsFormat.matches("accuracy %", label))
        guard fraction, let number = Double(value.trimmingCharacters(in: .whitespaces)), (0...1).contains(number) else { return value }
        return "\(Int((number * 100).rounded()))%"
    }

    nonisolated static func title(_ kind: SportsKind) -> String {
        switch kind {
        case .soccer, .hockey: String(localized: "Match Stats")
        case .tennis: String(localized: "Serve & Return")
        case .rugbyUnion, .rugbyLeague: String(localized: "Match Comparison")
        default: String(localized: "Team Comparison")
        }
    }

    /// The sport's six key statistics first (Expo `overviewComparisons`).
    nonisolated static func priorityRows(_ page: SportsGamePage) -> [SportsComparison] {
        let order = priorities[page.kind] ?? []
        let rank = { (label: String) in order.firstIndex { SportsFormat.matches($0, label) } ?? order.count }
        return Array(page.detail.comparisons.enumerated()
            .sorted { (rank($0.element.label), $0.offset) < (rank($1.element.label), $1.offset) }
            .map(\.element).prefix(6))
    }

    private nonisolated static let priorities: [SportsKind: [String]] = [
        .baseball: ["^hits$", "errors", "home runs", "strikeouts", "walks", "left on base"],
        .soccer: ["possession", "shots on target|shots on goal", "^shots$", "corners", "red cards", "yellow cards"],
        .hockey: ["shots on goal", "power.play goals", "power.play chances", "saves", "faceoff", "hits"],
        .tennis: ["aces", "double faults", "first serve", "break point", "winner", "unforced"],
        .mma: ["knockdown", "significant strikes landed", "takedowns landed", "control time", "total strikes landed"],
        .rugbyUnion: ["possession", "territory", "^tackles$", "met(?:er|re)s", "tries", "conversions"],
        .rugbyLeague: ["possession", "met(?:er|re)s", "^tackles$", "missed tackles", "clean breaks", "tries"],
    ]
}
