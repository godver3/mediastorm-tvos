import Foundation

/// Followed teams in the profile's sports preferences (`teamIds`), shared with the Expo app:
/// `"<league>:<team id>"`, with the game's league and the team's id as the feed sends it.
/// Standings rows can carry a provider-unprefixed id where game ids are prefixed (see
/// `SportsStandings.record`), so ids match on their last `:` part within the same league.
enum SportsTeamFollows {
    /// The id a team is saved under.
    static func id(league: String, teamID: String) -> String { "\(league):\(teamID)" }

    /// The last `:`-separated part of an id.
    static func lastPart(_ id: String) -> String { id.split(separator: ":").last.map(String.init) ?? id }

    /// Whether the stored follow `stored` is the team `teamID` of `league`.
    static func matches(_ stored: String, league: String, teamID: String) -> Bool {
        guard !league.isEmpty, !teamID.isEmpty, stored.hasPrefix("\(league):") else { return false }
        return stored == id(league: league, teamID: teamID) || lastPart(stored) == lastPart(teamID)
    }

    static func isFollowed(league: String, teamID: String, in teamIDs: [String]) -> Bool {
        teamIDs.contains { matches($0, league: league, teamID: teamID) }
    }

    /// The preferences with the team followed (saved as `league:teamID`) or every follow of it
    /// dropped; every other field as it was.
    static func setting(_ preferences: SportsPreferences, league: String, teamID: String, followed: Bool) -> SportsPreferences {
        var next = preferences
        if followed {
            if !isFollowed(league: league, teamID: teamID, in: next.teamIds) { next.teamIds.append(id(league: league, teamID: teamID)) }
        } else {
            next.teamIds.removeAll { matches($0, league: league, teamID: teamID) }
        }
        return next
    }

    /// The name on a Follow button: the nickname ("Timberwolves"), else the name, else the abbreviation.
    static func buttonName(_ team: SportsTeam) -> String {
        [team.nickname, team.name, team.abbreviation].lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
    }

    /// The preferences without a stored follow, nor any other id of the same team.
    static func unfollowing(_ preferences: SportsPreferences, stored: String) -> SportsPreferences {
        let league = league(stored)
        var next = preferences
        next.teamIds.removeAll { $0 == stored || matches($0, league: league, teamID: String(stored.dropFirst(league.count + 1))) }
        return next
    }

    /// A matchup of two teams that can be followed: not tennis, combat or golf (racing and
    /// cycling are not games).
    static func isTeamMatchup(_ game: SportsGame, kind: SportsKind) -> Bool {
        game.isMatchup && !kind.awayFirst && !game.homeTeam.id.isEmpty && !game.awayTeam.id.isEmpty
    }

    /// A team game in which a followed team plays (the hub's My Teams filter).
    static func playsFollowedTeam(_ game: SportsGame, kind: SportsKind, teamIDs: [String]) -> Bool {
        guard !teamIDs.isEmpty, isTeamMatchup(game, kind: kind) else { return false }
        return [game.homeTeam, game.awayTeam].contains { isFollowed(league: game.league, teamID: $0.id, in: teamIDs) }
    }

    /// The league part of a stored follow.
    static func league(_ stored: String) -> String {
        stored.split(separator: ":", maxSplits: 1).first.map(String.init) ?? stored
    }

    /// A followed team's name: from the league's standings if known, else from a game seen on
    /// the hub, else the raw id.
    static func name(_ stored: String, tables: [String: [SportsLeagueTable]], games: [SportsGame]) -> String {
        let league = league(stored)
        if let row = (tables[league] ?? []).lazy.flatMap(\.rows)
            .first(where: { $0.kind == "team" && matches(stored, league: league, teamID: $0.id) }) {
            return row.name
        }
        if let team = games.lazy.filter({ $0.league == league }).flatMap({ [$0.homeTeam, $0.awayTeam] })
            .first(where: { !$0.name.isEmpty && matches(stored, league: league, teamID: $0.id) }) {
            return team.name
        }
        return stored
    }

    /// A league's teams to follow from its standings: team rows, once each by id, by name.
    static func teams(_ tables: [SportsLeagueTable]) -> [SportsTableRow] {
        var seen = Set<String>()
        return tables.flatMap(\.rows).filter { $0.kind == "team" && !$0.id.isEmpty && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The leagues offered under Add Team: usable team-sport competitions (no racing, cycling,
    /// tennis, combat or golf), followed and pinned first, then in the catalog's order.
    static func teamLeagues(_ catalog: [SportsLeague], followed: [String], pinned: [String]) -> [SportsLeague] {
        catalog.enumerated()
            .filter { isTeamLeague($0.element) }
            .sorted { (SportsHubFilters.rank($0.element, followed: followed, pinned: pinned), $0.offset)
                < (SportsHubFilters.rank($1.element, followed: followed, pinned: pinned), $1.offset) }
            .map(\.element)
    }

    static func isTeamLeague(_ league: SportsLeague) -> Bool {
        guard league.isUsable, league.supportsTeams != false, !league.isRacing,
              SportsHubFilters.family(league) != SportsCycling.sport else { return false }
        let kind = SportsKind(rawValue: SportsHubFilters.family(league) ?? "") ?? SportsKind.kind(leagueID: league.id)
        return !kind.awayFirst
    }
}
