import SwiftUI

/// The feed's game leaders (Expo `CompactDetailLeaders`): up to four, each with the player's
/// headshot, side and category, and the figure (under the name when it is a long line).
struct SportsGameLeaders: View {
    let page: SportsGamePage

    var body: some View {
        SportsPanel(String(localized: "Game Leaders")) {
            ForEach(Array(page.detail.leaders.prefix(4).enumerated()), id: \.offset) { _, leader in
                let long = leader.value.count > 10
                HStack(spacing: 18) {
                    SportsPlayerPortrait(name: leader.name, headshot: leader.headshotUrl,
                                         team: page.team(abbreviation: leader.teamAbbreviation), size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(leader.name).fontWeight(.semibold).lineLimit(1)
                        Text("\(leader.teamAbbreviation) · \(leader.label)").font(.caption).foregroundStyle(.secondary)
                        if long { Text(leader.value).monospacedDigit() }
                    }
                    Spacer(minLength: 12)
                    if !long { Text(leader.value).font(.title3.weight(.semibold)).monospacedDigit() }
                }
                .sportsReadout()
            }
        }
    }
}

/// The standout lines of a result from the box score (Expo `SportsResultPerformers`):
/// baseball's top batter (by RBI, then hits) and pitcher (by innings) per side, hockey's
/// goalies (by saves, also while live). Never the provider's own leader rankings.
struct SportsResultPerformers: View {
    let page: SportsGamePage

    struct Entry {
        let team: SportsTeam
        let player: SportsPlayerStats
        let stats: [SportsStat]
    }

    var body: some View {
        SportsPanel(page.game.league == "mlb" ? String(localized: "Batting & Pitching") : String(localized: "Goalies")) {
            ForEach(Array(Self.entries(page).enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 18) {
                    SportsPlayerPortrait(name: entry.player.name, headshot: entry.player.headshotUrl, team: entry.team, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.player.name).fontWeight(.semibold).lineLimit(1)
                        Text(entry.stats.map { "\($0.value) \($0.label)" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .sportsReadout()
            }
        }
    }

    nonisolated static func entries(_ page: SportsGamePage) -> [Entry] {
        let league = page.game.league
        guard page.lifecycle == .final || (league == "nhl" && page.lifecycle == .live) else { return [] }
        guard league == "mlb" || league == "nhl" else { return [] }
        let categories = league == "mlb" ? ["Batting", "Pitching"] : ["Goalie"]
        return [page.game.awayTeam, page.game.homeTeam].flatMap { team in
            categories.compactMap { category -> Entry? in
                let players = page.detail.playerStats.filter { $0.teamId == team.id && $0.category == category }
                let value = { (player: SportsPlayerStats, label: String) in Double(player.value(label) ?? "") ?? 0 }
                let best = players.enumerated().max { a, b in
                    let x = category == "Batting" ? (value(a.element, "RBI"), value(a.element, "H"))
                        : (value(a.element, category == "Pitching" ? "IP" : "SV"), 0.0)
                    let y = category == "Batting" ? (value(b.element, "RBI"), value(b.element, "H"))
                        : (value(b.element, category == "Pitching" ? "IP" : "SV"), 0.0)
                    // The feed's first wins a tie.
                    return x != y ? x < y : a.offset > b.offset
                }?.element
                guard let best else { return nil }
                let keys = category == "Batting" ? ["H", "AB", "RBI", "HR"] : category == "Pitching" ? ["IP", "ER", "K"] : ["SV", "SA", "SV%"]
                return Entry(team: team, player: best, stats: best.stats.filter { keys.contains($0.label) })
            }
        }
    }
}
