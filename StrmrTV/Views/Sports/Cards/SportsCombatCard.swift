import SwiftUI

/// A fight on the hub (Expo `CombatBody`): both fighters' portraits and names either side of "VS",
/// the winner tagged, and the result (or the start). With scores hidden the result says so.
struct SportsCombatCard: View {
    let game: SportsGame
    let leagueName: String
    let spoilers: Bool
    var stale = false

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            SportsCardHeading(leagueName: leagueName, lifecycle: game.lifecycle)
            HStack(alignment: .top, spacing: 8) {
                fighter(game.awayTeam)
                Text("VS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 34)
                fighter(game.homeTeam)
            }
            Spacer(minLength: 0)
            Text(game.lifecycle == .scheduled ? SportsFormat.statusLine(game, spoilers: spoilers) : SportsCombatRules.result(game, hidden: spoilers))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
            if stale { SportsCardDelayed() }
        }
    }

    private func fighter(_ athlete: SportsTeam) -> some View {
        VStack(spacing: 6) {
            SportsPlayerPortrait(name: athlete.name, headshot: SportsCombatRules.portrait(league: game.league, fighter: athlete), size: 84)
            Text(athlete.name).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
            if !spoilers, game.lifecycle == .final, athlete.winner == true {
                Text("WINNER").font(.caption2.weight(.bold)).foregroundStyle(SportsCombatHeader.winner)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
