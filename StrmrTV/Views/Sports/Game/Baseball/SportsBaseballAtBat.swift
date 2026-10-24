import SwiftUI

/// MLB's live at-bat on the Overview (Expo `SportsBaseballOverview`'s at-bat panel with
/// `BaseballMatchup`): the batter, the diamond with the runners over the count, then the pitcher,
/// each with this game's line from the box score (and the pitcher's pitch count). Between
/// at-bats, the reported status instead. Three stops for the remote, left to right; a player
/// with a box-score line opens it on Select.
struct SportsBaseballAtBat: View {
    let page: SportsGamePage
    let state: SportsBaseballState

    @Environment(\.sportsShowPlayer) private var showPlayer

    var body: some View {
        let stale = page.isStale()
        SportsPanel(state.active ? (stale ? String(localized: "Last Reported At-Bat") : String(localized: "At Bat"))
                    : String(localized: "Game Situation")) {
            if state.active {
                HStack(alignment: .center, spacing: 20) {
                    card(SportsBaseballPlayer(page: page, state: state, pitcher: false))
                    VStack(spacing: 14) {
                        SportsBaseballDiamond(bases: state.situation?.occupiedBases, size: 140)
                        SportsBaseballCount(situation: state.situation, stale: stale)
                    }
                    .sportsReadout(fill: false)
                    .accessibilityLabel([state.situation?.bases ?? String(localized: "Base occupancy unavailable"), state.count, state.outs]
                        .compactMap { $0 }.joined(separator: " · "))
                    card(SportsBaseballPlayer(page: page, state: state, pitcher: true))
                }
            } else {
                Text(state.status).foregroundStyle(.secondary).sportsReadout()
            }
        }
    }

    @ViewBuilder private func card(_ player: SportsBaseballPlayer) -> some View {
        let target = player.line.flatMap { line in
            line.stats.isEmpty || !SportsGameTab.stats.isAvailable(for: page) ? nil
                : SportsPlayerTarget(teamID: line.teamId, playerID: line.id, category: line.category)
        }
        if let target, let showPlayer {
            Button { showPlayer(target) } label: { SportsBaseballPlayerCard(page: page, player: player, opens: true) }
                .buttonStyle(SportsReadoutButtonStyle())
                .padding(.horizontal, -16)
                .accessibilityIdentifier("sports-baseball-\(player.pitcher ? "pitcher" : "batter")")
        } else {
            SportsBaseballPlayerCard(page: page, player: player, opens: false).sportsReadout()
        }
    }
}

/// The batter or the pitcher of the at-bat, with their line in this game's box score.
struct SportsBaseballPlayer {
    let pitcher: Bool
    let name: String?
    let team: SportsTeam?
    let line: SportsPlayerStats?
    /// "AB 2 · H 1 · RBI 0" for the batter, "IP 5.0 · K 6 · P 94" for the pitcher.
    let summary: [String]

    init(page: SportsGamePage, state: SportsBaseballState, pitcher: Bool) {
        let situation = state.situation
        let id = pitcher ? situation?.pitcherId : situation?.batterId
        let team = pitcher ? state.pitching : state.batting
        let category = pitcher ? "Pitching" : "Batting"
        let line = id.flatMap { id in page.detail.playerStats.first { $0.id == id && $0.teamId == team?.id && $0.category == category } }
        var summary = (pitcher ? ["IP", "K"] : ["AB", "H", "RBI"]).compactMap { key in
            line?.stats.first { $0.label.uppercased() == key || (key == "K" && $0.label.uppercased() == "SO") }.map { "\(key) \($0.value)" }
        }
        if pitcher, let pitches = situation?.pitcherPitchCount, pitches >= 0 { summary.append("P \(pitches)") }
        self.pitcher = pitcher
        name = pitcher ? situation?.pitcher : situation?.batter
        self.team = team
        self.line = line
        self.summary = summary
    }
}

/// A player of the at-bat: role, portrait (the box score's headshot when there is one), name
/// over a stripe in the side's colour, and this game's line.
struct SportsBaseballPlayerCard: View {
    let page: SportsGamePage
    let player: SportsBaseballPlayer
    /// Whether Select opens the player's box-score line.
    let opens: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((player.pitcher ? String(localized: "PITCHER") : String(localized: "BATTER"))
                 + (player.line == nil ? "" : " · " + String(localized: "THIS GAME")))
                .font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                SportsPlayerPortrait(name: player.name ?? String(localized: "Player"), headshot: player.line?.headshotUrl,
                                     team: player.team, size: 72)
                VStack(alignment: .leading, spacing: 8) {
                    Text(player.name ?? String(localized: "Not supplied")).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                    if let team = player.team {
                        Capsule().fill(Color(hex: page.colorHex(team)) ?? .secondary).frame(width: 32, height: 3)
                    }
                }
            }
            if !player.summary.isEmpty {
                Text(player.summary.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if opens { Text("View game stats ›").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
