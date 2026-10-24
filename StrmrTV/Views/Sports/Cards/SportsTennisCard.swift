import SwiftUI

/// A tennis match on the hub (Expo `SportsTennisCard`): the tournament and round, then both
/// players (with seeds) over the games of each set and the sets won, the set in play tinted while
/// live, and the match's state. Scoreboards rarely carry the set scores, so the card says so;
/// with scores hidden only the names and the state show.
struct SportsTennisCard: View {
    let game: SportsGame
    let leagueName: String
    let spoilers: Bool
    var stale = false

    var body: some View {
        let scheduled = game.lifecycle == .scheduled
        let periods = spoilers || scheduled ? [] : game.detail?.periods ?? []
        let sets = !spoilers && !scheduled && (game.awayTeam.score != nil || game.homeTeam.score != nil)
        let latest = game.lifecycle == .live ? SportsTennis.latestSet(periods) : nil
        let context = SportsTennis.eventContext(game)?.components(separatedBy: " · ") ?? []
        VStack(alignment: .leading, spacing: 6) {
            SportsCardHeading(leagueName: leagueName, lifecycle: game.lifecycle)
            if let tournament = context.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tournament).font(.caption.weight(.medium)).lineLimit(1)
                    if context.count > 1 {
                        Text(context.dropFirst().joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Grid(alignment: .center, horizontalSpacing: 4, verticalSpacing: 2) {
                if !periods.isEmpty || sets {
                    GridRow {
                        Color.clear.frame(height: 1).gridCellUnsizedAxes([.horizontal, .vertical])
                        ForEach(periods.indices, id: \.self) { Text("S\($0 + 1)").frame(width: 34) }
                        if sets { Text("Sets").frame(width: 56) }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array([game.awayTeam, game.homeTeam].enumerated()), id: \.offset) { index, player in
                    GridRow {
                        Text(SportsTennis.name(player).replacingOccurrences(of: "\n", with: " / "))
                            .font(.callout.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(periods.enumerated()), id: \.offset) { set, period in
                            Text(SportsTennis.games(period, away: index == 0))
                                .font(.callout.weight(set == latest || SportsTennis.won(period, away: index == 0) ? .bold : .medium))
                                .frame(width: 34, height: 30)
                                .background(RoundedRectangle(cornerRadius: 7).fill(set == latest ? Color.white.opacity(0.16) : .clear))
                        }
                        if sets {
                            Text(player.score ?? "–").font(.headline).frame(width: 56)
                                .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1) }
                        }
                    }
                    .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8) }
            if !scheduled, !spoilers, periods.isEmpty {
                Text("Set scores not provided").font(.caption2).foregroundStyle(.secondary)
            }
            if stale { SportsCardDelayed() }
        }
    }

    /// The live state or reported result; a bare "Final" is left to the pill.
    private var status: String {
        if game.lifecycle != .scheduled, spoilers { return String(localized: "Scores hidden") }
        let line = SportsFormat.statusLine(game, spoilers: spoilers)
        return SportsFormat.matches("^(final|postponed|cancell?ed|delayed|tbd)$", line) ? "" : line
    }
}
