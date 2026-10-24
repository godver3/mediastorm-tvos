import SwiftUI

/// The live situation the scoreboard carries (Expo `SportsEditorialScoreboard`): for NFL and
/// college football, a football by the side with the ball, each side's timeouts under its score,
/// and the down and distance and the ball's spot under the clock; for MLB, the runners and the
/// outs and count under the inning (`BaseballSituationLine`); for basketball, possession and the
/// bonus, and for the NHL the strength and each side's shots (Expo `Situation`; the shots come from
/// the match stats when the feed sends no situation). Only while live with scores shown, so nothing
/// of it shows with scores hidden.
struct SportsHeaderSituation: Equatable {
    let football: SportsFootballSituation?
    let offense: SportsTeam?
    /// An at-bat under way.
    let baseball: SportsBaseballState?
    /// Basketball's and hockey's lines ("PHI possession", "Shots BOS 31 · NSH 28").
    let other: [String]
    let stale: Bool

    init(page: SportsGamePage, spoilers: Bool) {
        let shown = !spoilers && page.lifecycle == .live && page.game.showsScore
        let football = shown ? page.game.liveFootballSituation : nil
        let state = shown && page.game.league == "mlb" ? SportsBaseballState(game: page.game) : nil
        self.football = football
        offense = football?.offense(in: page.game)
        baseball = state?.active == true ? state : nil
        stale = page.isStale()
        other = shown ? Self.lines(page) : []
    }

    private static func lines(_ page: SportsGamePage) -> [String] {
        let game = page.game
        if let basketball = game.liveBasketballSituation {
            let side = game.side(named: basketball.possession)?.shortName ?? basketball.possession
            return [side.isEmpty ? nil : String(localized: "\(side) possession"), basketball.bonus].compactMap { $0 }
        }
        guard game.league == "nhl" else { return [] }
        let situation = game.liveHockeySituation
        let row = page.detail.comparisons.first { SportsFormat.matches(#"^shots on goal$"#, $0.label) }
        let shots = { (team: SportsTeam) -> String? in
            let home = team.id == game.homeTeam.id
            if let count = home ? situation?.shotsHome : situation?.shotsAway { return String(count) }
            return row.map { page.value($0, for: team) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let teams = page.teams
        let line = zip(teams, teams.map(shots)).allSatisfy { $0.1 != nil }
            ? String(localized: "Shots \(teams[0].shortName) \(shots(teams[0]) ?? "") · \(teams[1].shortName) \(shots(teams[1]) ?? "")") : nil
        return [situation?.strength.isEmpty == false ? situation?.strength : nil, line].compactMap { $0 }
    }

    func hasBall(_ team: SportsTeam) -> Bool { offense?.id == team.id }

    /// The lines under the clock: "3rd & 4" and "Ball at CHI 12", or "2 outs · Count 3–2".
    var lines: [String] {
        if let football { return [football.downDistance.isEmpty ? nil : football.downDistance, football.ballAt].compactMap { $0 } }
        if let line = baseball?.scoreboardLine(stale: stale) { return [line] }
        return other
    }
}

/// Under the clock: football's down and distance and the ball's spot, or baseball's runners
/// with the outs and the count.
struct SportsHeaderSituationLines: View {
    let situation: SportsHeaderSituation

    var body: some View {
        let lines = situation.lines
        if !lines.isEmpty {
            VStack(spacing: 6) {
                if let bases = situation.baseball?.situation?.occupiedBases {
                    SportsBasesGlyph(bases: bases, size: 22)
                }
                ForEach(lines, id: \.self) { Text($0) }
            }
            .multilineTextAlignment(.center)
            .font(.callout.weight(.semibold))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(([situation.baseball?.situation?.bases] + lines.map(Optional.some)).compactMap { $0 }.joined(separator: ", "))
        }
    }
}

/// A side's timeouts left under its score (Expo `FootballTimeouts`): "TO" and three lights, a
/// dash when the feed didn't say.
struct SportsTimeouts: View {
    let count: Int?
    let team: SportsTeam

    var body: some View {
        HStack(spacing: 7) {
            Text("TO").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if let count {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(index < count ? Color.accentColor : .clear)
                        .overlay(Circle().strokeBorder(Color.secondary, lineWidth: 1))
                        .frame(width: 11, height: 11)
                }
            } else {
                Text("—").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map { String(localized: "\(team.shortName): \($0) timeouts remaining") }
            ?? String(localized: "\(team.shortName): timeouts unknown"))
    }
}
