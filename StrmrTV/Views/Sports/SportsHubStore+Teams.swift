import Foundation

/// Followed teams on the hub: the My Teams filter and Follow on a game page (`SportsTeamFollows`).
extension SportsHubStore {
    var followedTeams: [String] { preferences?.preferences.teamIds ?? [] }

    func isFollowed(_ team: SportsTeam, in game: SportsGame) -> Bool {
        SportsTeamFollows.isFollowed(league: game.league, teamID: team.id, in: followedTeams)
    }

    /// The My Teams filter: a team game in which a followed team plays (no races or cycling).
    func playsFollowedTeam(_ item: SportsHubItem) -> Bool {
        guard case let .game(game) = item else { return false }
        return SportsTeamFollows.playsFollowedTeam(game, kind: kind(game), teamIDs: followedTeams)
    }

    /// Follows or unfollows a game's team at once (saved as `league:team.id`). Shown straight
    /// away; on failure the saved list comes back and the reason is returned.
    func setTeam(_ team: SportsTeam, in game: SportsGame, followed: Bool) async -> String? {
        guard let base = preferences, !savingTeams else { return nil }
        let next = SportsPreferencesSave.edited(base) {
            $0 = SportsTeamFollows.setting($0, league: game.league, teamID: team.id, followed: followed)
        }
        preferences = next
        savingTeams = true
        defer { savingTeams = false }
        switch await SportsPreferencesSave.save(next) {
        case let .saved(saved):
            preferences = saved
            return nil
        case let .conflict(reloaded):
            preferences = reloaded ?? base
            return SportsPreferencesSave.conflictMessage
        case let .failed(text):
            preferences = base
            return text
        }
    }
}
