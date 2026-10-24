import XCTest
@testable import StrmrTV

/// The game page's tabs follow the Expo TV page (`SportsGameDetailTV` `availableTab`): Drives
/// for NFL / college football with drives, Lineups for soccer with lineups, stats and plays by
/// the detail's capabilities (no stats for golf tournaments or cricket), Standings when a table
/// came along, and no tabs at all with scores hidden.
final class SportsGameTabTests: XCTestCase {
    private typealias F = SportsGameFixtures

    func testFootballFinalTabsAndLabels() {
        let page = F.page(detail: F.nflDetail)
        XCTAssertEqual(SportsGameTab.available(for: page, spoilers: false), [.overview, .drives, .stats, .plays])
        XCTAssertEqual(SportsGameTab.stats.label(page.kind), "Box Score")
        XCTAssertEqual(SportsGameTab.plays.label(page.kind), "Play-by-Play")
    }

    func testSpoilersHideEveryTab() {
        XCTAssertEqual(SportsGameTab.available(for: F.page(detail: F.nflDetail), spoilers: true), [])
    }

    func testDrivesOnlyForNFLAndCollegeFootball() {
        var detail = F.nflDetail
        detail["footballDrives"] = []
        XCTAssertFalse(SportsGameTab.drives.isAvailable(for: F.page(detail: detail)), "no drives sent")
        let other = F.page(["league": "espn:football:ufl"], detail: F.nflDetail)
        XCTAssertEqual(other.kind, .football)
        XCTAssertFalse(SportsGameTab.drives.isAvailable(for: other))
        XCTAssertTrue(SportsGameTab.drives.isAvailable(for: F.page(["league": "college-football"], detail: F.nflDetail)))
    }

    func testSoccerTabsAndLabels() {
        let detail: [String: Any] = [
            "capabilities": ["plays": true, "stats": true],
            "lineups": [["teamId": "3", "formation": "4-3-3", "players": [["id": "1", "name": "A Keeper", "starter": true]]]],
            "standings": [["title": "English Premier League Standings", "rows": [["teamId": "3", "name": "Chicago", "rank": "1"]]]],
        ]
        let page = F.page(["league": "soccer-eng.1", "sport": "soccer"], detail: detail)
        XCTAssertEqual(SportsGameTab.available(for: page, spoilers: false), [.overview, .lineups, .stats, .plays, .standings])
        XCTAssertEqual(SportsGameTab.stats.label(page.kind), "Match Stats")
        XCTAssertEqual(SportsGameTab.plays.label(page.kind), "Commentary")
        // Rugby lineups belong to its Overview (Expo's rugby overview), not a tab.
        let rugby = F.page(["league": "rugby-180659", "sport": "rugby"], detail: detail)
        XCTAssertEqual(rugby.kind, .rugbyUnion)
        XCTAssertFalse(SportsGameTab.lineups.isAvailable(for: rugby))
    }

    func testNoStatsTabForGolfTournamentsAndCricket() {
        let detail: [String: Any] = ["capabilities": ["plays": false, "stats": true]]
        let pga = F.league(#"{"id":"pga","enabled":true,"applicationSport":"golf","adapter":"tournament","eventKind":"tournament","supportsTeams":false}"#)
        let golf = F.page(["league": "pga", "sport": "golf"], detail: detail, league: pga)
        XCTAssertTrue(golf.isIndividualGolf)
        XCTAssertEqual(SportsGameTab.available(for: golf, spoilers: false), [.overview])
        let cricket = F.page(["league": "cricket-8048", "sport": "cricket"], detail: detail)
        XCTAssertEqual(SportsGameTab.available(for: cricket, spoilers: false), [.overview])
        let teamGolf = F.league(#"{"id":"cup","enabled":true,"applicationSport":"golf","adapter":"team-golf","eventKind":"matchup"}"#)
        XCTAssertTrue(SportsGameTab.stats.isAvailable(for: F.page(["league": "cup"], detail: detail, league: teamGolf)))
    }

    func testScheduledGameShowsOverviewAndAnyTable() {
        let page = F.page(["status": "scheduled", "statusDetail": "Sun, October 25th at 9:30 AM EDT"],
                          detail: ["capabilities": ["plays": false, "stats": false, "winProbability": false],
                                   "standings": [["title": "Table", "rows": []]]])
        XCTAssertEqual(SportsGameTab.available(for: page, spoilers: false), [.overview, .standings])
    }

    func testPickedTabIsKeptButShownOnlyWithData() {
        XCTAssertEqual(SportsGameTab.shown(.plays, in: [.overview, .stats, .plays]), .plays)
        XCTAssertEqual(SportsGameTab.shown(.plays, in: [.overview, .stats]), .overview)
        XCTAssertEqual(SportsGameTab.shown(.standings, in: []), .overview)
    }

    func testSportFamily() {
        let catalog = F.league(#"{"id":"nhl","enabled":true,"applicationSport":"ice-hockey"}"#)
        XCTAssertEqual(F.page(["league": "nhl", "sport": "hockey"], league: catalog).kind, .hockey)
        XCTAssertEqual(F.page(["league": "nhl", "sport": "hockey"]).kind, .hockey, "the feed's own sport name")
        XCTAssertEqual(F.page(["league": "nba", "sport": NSNull()]).kind, .basketball, "the league id when the feed has none")
        XCTAssertEqual(F.page(["league": "rugby-league-3", "sport": NSNull()]).kind, .rugbyLeague)
        XCTAssertEqual(F.page(["league": "soccer-usa.nwsl", "sport": NSNull()]).kind, .soccer)
    }

    func testDisplayOrderPutsHomeFirstForTeamSports() {
        XCTAssertEqual(F.page().teams.map(\.shortName), ["CHI", "NE"])
        XCTAssertEqual(F.page(["league": "atp", "sport": "tennis"]).teams.map(\.shortName), ["NE", "CHI"], "away first for tennis")
    }
}
