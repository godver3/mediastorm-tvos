import SwiftUI

/// A tennis match's set scores (Expo `SportsTennisSetScores`, the tennis Overview's line score):
/// each player (with the seed) over the games of every set, tiebreak points in superscript, the
/// sets won at the end; the set in play is tinted while live. One stop for the remote.
struct SportsTennisSetScores: View {
    let page: SportsGamePage

    var body: some View {
        let periods = page.detail.periods
        let live = page.lifecycle == .live
        let latest = SportsTennis.latestSet(periods)
        SportsPanel(String(localized: "Set Scores"), note: page.lifecycle == .final ? String(localized: "Final") : nil) {
            VStack(alignment: .leading, spacing: 0) {
                if live, let latest {
                    Text("Set \(latest + 1) · \(page.isStale() ? String(localized: "Last reported") : String(localized: "Live"))")
                        .font(.caption.weight(.semibold)).foregroundStyle(SportsTennis.accent)
                        .padding(.bottom, 10)
                }
                Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        Text("Player").gridColumnAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(periods.indices, id: \.self) { index in
                            Text("Set \(index + 1)").foregroundStyle(live && index == latest ? SportsTennis.accent : .secondary)
                                .frame(width: 92)
                        }
                        Text("Sets").frame(width: 92)
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
                    ForEach(Array(page.teams.enumerated()), id: \.offset) { _, player in
                        Divider().gridCellUnsizedAxes(.horizontal)
                        row(player, periods: periods, latest: live ? latest : nil)
                    }
                }
                .monospacedDigit()
            }
            .sportsReadout()
            .accessibilityLabel(accessibility(periods))
        }
    }

    private func row(_ player: SportsTeam, periods: [SportsPeriodScore], latest: Int?) -> some View {
        let away = player.id == page.game.awayTeam.id
        return GridRow {
            Text(SportsTennis.name(player)).font(.headline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(periods.enumerated()), id: \.offset) { index, period in
                Text(SportsTennis.games(period, away: away))
                    .font(.system(size: 34, weight: index == latest ? .bold : SportsTennis.won(period, away: away) ? .semibold : .regular))
                    .frame(width: 92)
                    .frame(maxHeight: .infinity)
                    .background(index == latest ? SportsTennis.accent.opacity(0.08) : .clear)
                    .overlay(alignment: .bottom) {
                        if index == latest, player.id == page.teams.last?.id {
                            Rectangle().fill(SportsTennis.accent).frame(height: 2)
                        }
                    }
            }
            Text(player.score ?? "–").font(.system(size: 38, weight: .bold)).frame(width: 92)
                .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1) }
        }
    }

    private func accessibility(_ periods: [SportsPeriodScore]) -> String {
        let players = page.teams.map { player in
            let away = player.id == page.game.awayTeam.id
            let sets = periods.map { SportsTennis.games($0, away: away) }.joined(separator: ", ")
            return String(localized: "\(SportsTennis.name(player)): \(sets). Sets won: \(player.score ?? "unknown")")
        }
        return ([String(localized: "Set scores")] + players).joined(separator: ". ")
    }
}

/// The set scores under the header's status (the tennis scoreboard): one compact row per player in
/// display order, games per set with tiebreaks, the set in play in the tennis accent while live.
struct SportsTennisHeaderSets: View {
    let page: SportsGamePage

    static func shows(_ page: SportsGamePage, spoilers: Bool) -> Bool {
        page.kind == .tennis && !spoilers && page.lifecycle != .scheduled && !page.detail.periods.isEmpty
    }

    var body: some View {
        let periods = page.detail.periods
        let latest = page.lifecycle == .live ? SportsTennis.latestSet(periods) : nil
        Grid(horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(Array(page.teams.enumerated()), id: \.offset) { _, player in
                let away = player.id == page.game.awayTeam.id
                GridRow {
                    ForEach(Array(periods.enumerated()), id: \.offset) { index, period in
                        Text(SportsTennis.games(period, away: away))
                            .fontWeight(index == latest || SportsTennis.won(period, away: away) ? .bold : .regular)
                            .foregroundStyle(index == latest ? SportsTennis.accent : .primary)
                    }
                }
            }
        }
        .font(.callout).monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Set scores"))
    }
}
