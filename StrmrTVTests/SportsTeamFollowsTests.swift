import XCTest
@testable import StrmrTV

/// Followed teams: id matching (prefixed / unprefixed), saving a follow without touching the
/// rest of the preferences, the hub's My Teams filter, and Customize's team lists.
@MainActor
final class SportsTeamFollowsTests: XCTestCase {
    private typealias F = SportsTeamFollows

    func testMatchesExactAndLastPartWithinLeague() {
        XCTAssertTrue(F.isFollowed(league: "nba", teamID: "13", in: ["nba:13"]))
        // Game id provider-prefixed, stored from standings unprefixed, and the other way round.
        XCTAssertTrue(F.isFollowed(league: "nba", teamID: "espn:13", in: ["nba:13"]))
        XCTAssertTrue(F.isFollowed(league: "nba", teamID: "13", in: ["nba:espn:13"]))
        XCTAssertTrue(F.isFollowed(league: "nba", teamID: "espn:13", in: ["nba:espn:13"]))
        // Another league, another team, or nothing to match.
        XCTAssertFalse(F.isFollowed(league: "wnba", teamID: "13", in: ["nba:13"]))
        XCTAssertFalse(F.isFollowed(league: "nba", teamID: "131", in: ["nba:13"]))
        XCTAssertFalse(F.isFollowed(league: "nba", teamID: "", in: ["nba:"]))
        XCTAssertFalse(F.isFollowed(league: "nba", teamID: "13", in: []))
    }

    func testSettingKeepsOtherFields() {
        var prefs = SportsPreferences()
        prefs.pinnedSportIds = ["basketball"]
        prefs.competitionIds = ["nba", "premier-league"]
        prefs.teamIds = ["nfl:3", "nba:espn:13"]
        prefs.athleteIds = ["a1"]
        prefs.schools = [SportsSchoolFollow(schoolId: "s1", scope: "all", programIds: nil)]

        let followed = F.setting(prefs, league: "nhl", teamID: "espn:7", followed: true)
        XCTAssertEqual(followed.teamIds, ["nfl:3", "nba:espn:13", "nhl:espn:7"])
        var expected = prefs
        expected.teamIds = followed.teamIds
        XCTAssertEqual(followed, expected)
        // Already followed under another form: not added twice.
        XCTAssertEqual(F.setting(prefs, league: "nba", teamID: "13", followed: true).teamIds, prefs.teamIds)
        // Unfollow drops every form of it, nothing else.
        let unfollowed = F.setting(prefs, league: "nba", teamID: "13", followed: false)
        XCTAssertEqual(unfollowed.teamIds, ["nfl:3"])
        XCTAssertEqual(unfollowed.competitionIds, prefs.competitionIds)
        XCTAssertEqual(unfollowed.schools, prefs.schools)

        // Customize's Unfollow drops every stored form of the team.
        var both = prefs
        both.teamIds = ["nba:13", "nba:espn:13", "nba:14"]
        XCTAssertEqual(F.unfollowing(both, stored: "nba:13").teamIds, ["nba:14"])
        XCTAssertEqual(F.unfollowing(both, stored: "nba:13").schools, prefs.schools)

        let envelope = SportsPreferencesEnvelope(revision: 7, preferences: prefs)
        let edited = SportsPreferencesSave.edited(envelope) { $0 = F.setting($0, league: "nfl", teamID: "3", followed: false) }
        XCTAssertEqual(edited.revision, 7)
        XCTAssertEqual(edited.preferences.athleteIds, ["a1"])
        XCTAssertEqual(edited.preferences.teamIds, ["nba:espn:13"])
    }

    private func game(_ id: String, league: String = "nfl", home: String = "3", away: String = "17",
                      status: String = "scheduled", extra: [String: Any] = [:]) -> SportsGame {
        var overrides: [String: Any] = ["id": id, "league": league, "status": status, "statusDetail": status,
                                        "startTime": "2026-11-08T19:00:00Z"]
        overrides["homeTeam"] = ["id": home, "name": "Home \(home)", "abbreviation": "H\(home)"]
        overrides["awayTeam"] = ["id": away, "name": "Away \(away)", "abbreviation": "A\(away)"]
        overrides.merge(extra) { $1 }
        return SportsGameFixtures.game(overrides)
    }

    private func league(_ id: String, sport: String) -> SportsLeague {
        SportsGameFixtures.league(#"{"id":"\#(id)","enabled":true,"name":"\#(id.uppercased())","applicationSport":"\#(sport)"}"#)
    }

    func testButtonNameIsNicknameElseNameElseAbbreviation() {
        func team(_ json: [String: Any]) -> SportsTeam { SportsGameFixtures.decode(SportsTeam.self, json) }
        XCTAssertEqual(F.buttonName(team(["id": "1", "name": "Minnesota Timberwolves", "nickname": "Timberwolves",
                                          "abbreviation": "MIN"])), "Timberwolves")
        XCTAssertEqual(F.buttonName(team(["id": "1", "name": "Minnesota Timberwolves", "nickname": " ", "abbreviation": "MIN"])),
                       "Minnesota Timberwolves")
        XCTAssertEqual(F.buttonName(team(["id": "1", "name": "", "abbreviation": "MIN"])), "MIN")
    }

    func testTeamMatchupsOnly() {
        XCTAssertTrue(F.isTeamMatchup(game("1"), kind: .football))
        XCTAssertFalse(F.isTeamMatchup(game("1"), kind: .tennis))
        XCTAssertFalse(F.isTeamMatchup(game("1"), kind: .mma))
        XCTAssertFalse(F.isTeamMatchup(game("1", home: ""), kind: .football))
        XCTAssertTrue(F.playsFollowedTeam(game("1", away: "espn:17"), kind: .football, teamIDs: ["nfl:17"]))
        XCTAssertFalse(F.playsFollowedTeam(game("1"), kind: .football, teamIDs: ["nba:17"]))
        XCTAssertFalse(F.playsFollowedTeam(game("1"), kind: .tennis, teamIDs: ["nfl:17"]))
    }

    func testMyTeamsFilter() {
        let store = SportsHubStore()
        store.seed(games: [game("a"), game("b", home: "8", away: "9"), game("c", status: "final"),
                           game("d", league: "nba", home: "17", away: "2")],
                   catalog: [league("nfl", sport: "american-football"), league("nba", sport: "basketball")])
        store.preferences = SportsPreferencesEnvelope(revision: 1, preferences: SportsPreferences(competitionIds: ["nba"], teamIds: ["nfl:17"]))
        func ids() -> [String] { store.sections.flatMap(\.items).map(\.id).sorted() }

        XCTAssertEqual(ids(), ["a", "b", "c", "d"])
        store.myTeamsOnly = true
        XCTAssertEqual(ids(), ["a", "c"])
        // Still under All / Live / Upcoming / Results and the League filter.
        store.filter = .results
        XCTAssertEqual(ids(), ["c"])
        store.filter = .all
        store.league = "nba"
        XCTAssertEqual(ids(), [])
        store.league = SportsHubFilters.all

        // Following and My Teams are exclusive.
        store.followingOnly = true
        XCTAssertFalse(store.myTeamsOnly)
        XCTAssertEqual(ids(), ["a", "c", "d"])
        store.myTeamsOnly = true
        XCTAssertFalse(store.followingOnly)

        // Nothing followed: nothing shows (the hub says how to follow one).
        store.preferences?.preferences.teamIds = []
        XCTAssertEqual(ids(), [])
        XCTAssertTrue(store.followedTeams.isEmpty)
    }

    private func tables(_ rows: [[String: Any]]) -> [SportsLeagueTable] {
        [SportsGameFixtures.decode(SportsLeagueTable.self, ["id": "t", "rows": rows])]
    }

    func testCustomizeTeamListsAndNames() {
        let t = tables([["id": "2", "name": "Wolves"], ["id": "1", "name": "Bears"], ["id": "2", "name": "Wolves"],
                        ["id": "x", "name": "Driver", "kind": "athlete"]])
        XCTAssertEqual(F.teams(t).map(\.name), ["Bears", "Wolves"])

        let games = [game("a", home: "espn:5")]
        XCTAssertEqual(F.name("nfl:1", tables: ["nfl": t], games: games), "Bears")
        XCTAssertEqual(F.name("nfl:5", tables: [:], games: games), "Home espn:5")
        XCTAssertEqual(F.name("nfl:99", tables: ["nfl": t], games: games), "nfl:99")

        let catalog = [league("nfl", sport: "american-football"), league("atp", sport: "tennis"), league("nba", sport: "basketball"),
                       league("ufc", sport: "mma"), league("f1", sport: "racing")]
        XCTAssertEqual(F.teamLeagues(catalog, followed: [], pinned: []).map(\.id), ["nfl", "nba"])
        XCTAssertEqual(F.teamLeagues(catalog, followed: ["nba"], pinned: []).map(\.id), ["nba", "nfl"])
    }
}
