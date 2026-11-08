import SwiftUI

/// Follow / Following for each team of a team-sport matchup, in the game page's action row
/// (home side first, as the scoreboard). A press saves at once; on failure the button goes
/// back and `onFailure` gets the reason.
struct SportsFollowTeamButtons: View {
    let game: SportsGame
    @ObservedObject var hub: SportsHubStore
    let onFailure: (String) -> Void

    var body: some View {
        if hub.preferences != nil, SportsTeamFollows.isTeamMatchup(game, kind: hub.kind(game)) {
            ForEach([game.homeTeam, game.awayTeam], id: \.id) { team in
                let followed = hub.isFollowed(team, in: game)
                Button {
                    Task {
                        if let failure = await hub.setTeam(team, in: game, followed: !followed) { onFailure(failure) }
                    }
                } label: {
                    if followed {
                        Label("Following \(SportsTeamFollows.buttonName(team))", systemImage: "checkmark")
                    } else {
                        Text("Follow \(SportsTeamFollows.buttonName(team))")
                    }
                }
                .disabled(hub.savingTeams)
                .accessibilityIdentifier("sports-follow-team-\(team.id)")
            }
        }
    }
}
