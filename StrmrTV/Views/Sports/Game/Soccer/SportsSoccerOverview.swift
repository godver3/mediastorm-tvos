import SwiftUI

/// The Overview of soccer matches (Expo `SportsSportOverview`'s soccer branch): before kick-off the
/// published formations on the pitch; once under way the goals and latest event and the match
/// stats, beside the formations (pitch in Lineups) and the match information. A match not under
/// way opens with the availability notice; a scheduled one ends with the matchup preview.
struct SportsSoccerOverview: View {
    let page: SportsGamePage

    private enum Panel: Hashable { case availability, pitch, timeline, stats, formations, info }

    var body: some View {
        let scheduled = page.lifecycle == .scheduled
        let left = (scheduled ? [Panel.availability, .pitch] : [.availability, .timeline, .stats]).filter(shows)
        let right = (scheduled ? [Panel.info] : [.formations, .info]).filter(shows)
        VStack(alignment: .leading, spacing: 40) {
            SportsColumns(weights: [1.2, 1]) {
                if !left.isEmpty { column(left) }
                if !right.isEmpty { column(right) }
            }
            if scheduled {
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

    private func shows(_ panel: Panel) -> Bool {
        switch panel {
        case .availability: return SportsAvailabilityNotice.applies(page)
        case .pitch, .formations: return !page.detail.lineups.isEmpty
        case .timeline: return SportsSoccerTimeline.latest(page) != nil
        case .stats: return page.lifecycle != .scheduled && !page.detail.comparisons.isEmpty
        case .info: return !SportsMatchInfo.items(page).isEmpty || SportsMatchInfo.hasNotes(page)
        }
    }

    @ViewBuilder private func panel(_ panel: Panel) -> some View {
        switch panel {
        case .availability: SportsAvailabilityNotice(page: page)
        case .pitch: SportsSoccerPitch(page: page)
        case .timeline: SportsSoccerTimeline(page: page)
        case .stats: SportsSoccerStats(page: page, rows: SportsTeamComparison.priorityRows(page))
        case .formations: SportsSoccerPitch(page: page, summaryOnly: true)
        case .info: SportsMatchInfo(page: page)
        }
    }
}

/// Soccer's match stats (Expo `SportsPriorityStats`, soccer variant): the sides' crests, possession
/// as one bar split between the team colours (when the two shares add up to 100), then each
/// statistic's figures around its name. One stop per row.
struct SportsSoccerStats: View {
    let page: SportsGamePage
    let rows: [SportsComparison]
    var title = String(localized: "Match Stats")

    /// Both shares as percentages adding up to 100 (±1), else nil.
    nonisolated static func possession(_ left: String, _ right: String) -> (Double, Double)? {
        let number = { (text: String) in Double(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
        guard let a = number(left), let b = number(right), (0...100).contains(a), (0...100).contains(b), abs(a + b - 100) <= 1 else {
            return nil
        }
        return (a, b)
    }

    var body: some View {
        let teams = page.teams
        let colors = teams.map { SportsTeamColors.color($0, in: page.game) }
        let possession = rows.first { SportsFormat.matches("possession", $0.label) }
        SportsPanel(title) {
            HStack(spacing: 12) {
                SportsTeamLogo(team: teams[0], size: 36)
                Text(teams[0].shortName)
                Spacer()
                Text(teams[1].shortName)
                SportsTeamLogo(team: teams[1], size: 36)
            }
            .fontWeight(.semibold)
            if let possession {
                let values = teams.map { page.value(possession, for: $0) }
                let shares = Self.possession(values[0], values[1])
                VStack(spacing: 10) {
                    HStack {
                        Text(shares.map { "\(Self.format($0.0))%" } ?? values[0]).fontWeight(.semibold)
                        Spacer()
                        Text("Possession").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(shares.map { "\(Self.format($0.1))%" } ?? values[1]).fontWeight(.semibold)
                    }
                    if let shares {
                        GeometryReader { proxy in
                            HStack(spacing: 0) {
                                Rectangle().fill(colors[0]).frame(width: proxy.size.width * shares.0 / (shares.0 + shares.1))
                                Rectangle().fill(colors[1])
                            }
                        }
                        .frame(height: 8)
                        .clipShape(Capsule())
                        .accessibilityHidden(true)
                    }
                }
                .monospacedDigit()
                .sportsReadout()
            }
            ForEach(Array(rows.filter { $0 != possession }.enumerated()), id: \.offset) { _, row in
                SportsColumns(weights: [1, 3, 1], spacing: 12) {
                    Text(Self.display(page.value(row, for: teams[0]), label: row.label)).fontWeight(.bold).frame(maxWidth: .infinity)
                    Text(row.label).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Text(Self.display(page.value(row, for: teams[1]), label: row.label)).fontWeight(.bold).frame(maxWidth: .infinity)
                }
                .monospacedDigit()
                .sportsReadout()
            }
        }
    }

    /// Accuracy comes as a fraction (0.83): shown as a percentage.
    nonisolated static func display(_ value: String, label: String) -> String {
        guard SportsFormat.matches("accuracy %", label), let number = Double(value.trimmingCharacters(in: .whitespaces)),
              (0...1).contains(number) else { return value }
        return "\(Int((number * 100).rounded()))%"
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}
