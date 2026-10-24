import XCTest
@testable import StrmrTV

/// The game page's reading of a game's `detail` (Go `models.SportsGameDetail`, Expo
/// `sports-backend-source.ts` / `sports-model.ts`): lenient lists, the box score's tables, the
/// pre-game context kept with scores hidden (`sportsSpoilerContext`) and the page's wording.
final class SportsDetailModelTests: XCTestCase {
    private typealias F = SportsGameFixtures

    func testDecodesTheDetailLeniently() {
        let detail = F.page(detail: F.nflDetail).detail
        XCTAssertEqual(detail.capabilities, SportsCapabilities(plays: true, stats: true))
        XCTAssertEqual(detail.periods.map(\.away), ["0", "14"], "a number reads as text")
        XCTAssertEqual(detail.plays.map(\.id), ["1", "2", "3"], "the play without an id is skipped")
        XCTAssertFalse(detail.plays[2].scoring, "no scoring flag is not scoring")
        XCTAssertEqual(detail.plays[1].teamId, "17")
        XCTAssertEqual(detail.playerStats.count, 5)
        XCTAssertTrue(detail.playerStats[4].stats.isEmpty, "null stats are empty")
        XCTAssertEqual(detail.footballDrives.first?.plays.first?.type, "Kickoff")
        XCTAssertEqual(detail.footballDrives.last?.playCount, nil)
        XCTAssertEqual(detail.pregame?.teams.map(\.teamId), ["17", "3"])
    }

    func testEmptyAndNullDetail() {
        let detail = F.decode(SportsGameDetail.self, #"{"periods": null, "plays": null, "comparisons": null, "capabilities": {}}"#)
        XCTAssertEqual(detail, SportsGameDetail())
        XCTAssertEqual(F.page().detail, SportsGameDetail(), "a game without detail")
        XCTAssertFalse(F.page().isStale(), "no detail, nothing stale")
    }

    func testStandingsLineupsAndPregameDecode() {
        let detail = F.decode(SportsGameDetail.self, """
        {"standings": [{"title": "English Premier League Standings", "rows": [
            {"teamId": "382", "name": "Manchester City", "rank": "1", "played": "5", "points": 15, "goalDifference": "+8"},
            {"name": "No team id"}, {"teamId": "359"}]}],
         "lineups": [{"teamId": "379", "formation": "5-4-1", "players": [
            {"id": "126703", "name": "Martin Dúbravka", "number": "1", "position": "Goalkeeper", "starter": true},
            {"id": "207146", "name": "Josh Cullen", "number": 24, "starter": true, "subbedOut": true},
            {"id": "x"}]}],
         "pregame": {"seasonLabel": "2026 · Postseason", "updatedAt": "2026-10-23T08:21:39-06:00",
            "teams": [{"teamId": "30", "record": "98-64", "rank": 3, "standingStats": [{"label": "Streak", "value": "L1"}],
                       "recent": [{"id": "401908028", "date": "2026-10-20T00:00:00Z", "opponent": "Cleveland Guardians", "result": "W", "score": "7-3"}],
                       "probables": [{"name": "Nick Martinez", "label": "Probable starting pitcher"}]}],
            "comparisons": [{"label": "ERA", "away": "3.70", "home": "3.51"}],
            "previousMeeting": {"date": "2026-04-01T17:40:00Z", "homeTeamId": "8", "awayTeamId": "30", "homeScore": "8", "awayScore": 2}}}
        """)
        XCTAssertEqual(detail.standings.first?.rows.map(\.name), ["Manchester City", "No team id"])
        XCTAssertEqual(detail.standings.first?.rows.first?.points, "15")
        XCTAssertEqual(detail.lineups.first?.players.map(\.name), ["Martin Dúbravka", "Josh Cullen"])
        XCTAssertEqual(detail.lineups.first?.players.last?.number, "24")
        XCTAssertTrue(detail.lineups.first?.players.last?.subbedOut ?? false)
        let team = detail.pregame?.team("30")
        XCTAssertEqual(team?.rank, 3)
        XCTAssertEqual(team?.recent.first?.opponent, "Cleveland Guardians")
        XCTAssertEqual(team?.probables.first?.value, nil)
        XCTAssertEqual(detail.pregame?.previousMeeting?.awayScore, "2")
    }

    func testSpoilerSafePregame() {
        let pregame = SportsPregame(
            seasonLabel: "2026", updatedAt: "2026-10-22T12:00:00Z",
            teams: [SportsPregameTeam(teamId: "3", record: "5-2",
                                      recent: [SportsRecentResult(id: "old", date: "2026-10-15T00:00:00Z", opponent: "A", result: "W", score: "1-0"),
                                               SportsRecentResult(id: "game", date: "2026-10-22T23:00:00Z", opponent: "B", result: "L", score: "0-1"),
                                               SportsRecentResult(id: "later", date: "2026-10-30T00:00:00Z", opponent: "C", result: "W", score: nil)])],
            comparisons: [SportsComparison(label: "Points per game", away: "20", home: "24")])
        let start = SportsGame.date("2026-10-23T00:15:00Z")!
        let before = pregame.spoilerSafe(start: start, eventID: "game")
        XCTAssertEqual(before.teams.first?.record, "5-2", "a snapshot from before the start keeps its records")
        XCTAssertEqual(before.teams.first?.recent.map(\.id), ["old"], "never this game or later ones")
        XCTAssertEqual(before.comparisons.count, 1)
        var later = pregame
        later.updatedAt = "2026-10-23T08:00:00Z"
        later.previousMeeting = F.decode(SportsPreviousMeeting.self,
                                         #"{"date":"2026-10-23T03:00:00Z","homeTeamId":"3","awayTeamId":"17","homeScore":"30","awayScore":"24"}"#)
        let after = later.spoilerSafe(start: start, eventID: "game")
        XCTAssertNil(after.teams.first?.record, "a later snapshot keeps only earlier results")
        XCTAssertEqual(after.teams.first?.recent.map(\.id), ["old"])
        XCTAssertTrue(after.comparisons.isEmpty)
        XCTAssertNil(after.previousMeeting)
    }

    func testBoxScoreTablesPerSideAndCategory() {
        let stats = F.page(detail: F.nflDetail).detail.playerStats
        let tables = SportsBoxScoreTable.tables(teamID: "17", stats: stats)
        XCTAssertEqual(tables.map(\.category), ["Passing", "Rushing"])
        XCTAssertEqual(tables[1].columns, ["CAR", "YDS", "TD"], "every column a category's rows use, in order")
        XCTAssertEqual(tables[1].rows.map(\.name), ["Drake Maye", "Rhamondre Stevenson"])
        XCTAssertEqual(SportsBoxScoreTable.tables(teamID: "3", stats: stats).map(\.category), ["Passing"], "rows without stats are left out")
        XCTAssertEqual(SportsBoxScoreTable.heading("SACK-YDS"), "SACK / YDS")
    }

    func testStatusWording() {
        XCTAssertEqual(SportsFormat.detailStatus(F.page()), "Final")
        XCTAssertEqual(SportsFormat.detailStatus(F.page(["status": "live", "statusDetail": "Q3 5:21", "period": "Q3", "clock": "5:21"])),
                       "Q3 · 5:21")
        let hockey = ["league": "nhl", "sport": "hockey"]
        XCTAssertEqual(SportsFormat.detailStatus(F.page(hockey.merging(["statusDetail": "Final/OT", "period": "OT"]) { $1 })), "Final · Overtime")
        XCTAssertEqual(SportsFormat.detailStatus(F.page(hockey.merging(["status": "live", "period": "P2", "clock": "12:00"]) { $1 })),
                       "2nd period · 12:00")
        let soccer: [String: Any] = ["league": "soccer-eng.1", "sport": "soccer", "statusDetail": "FT", "period": "FT"]
        XCTAssertEqual(SportsFormat.detailStatus(F.page(soccer)), "Full time")
        XCTAssertEqual(SportsFormat.detailStatus(F.page(soccer.merging(["statusDetail": "AET"]) { $1 })), "Full time · After extra time")
        let shootout = soccer.merging(["homeTeam": ["id": "1", "name": "A", "score": "3", "shootoutScore": 4],
                                       "awayTeam": ["id": "2", "name": "B", "score": "3", "shootoutScore": 2]]) { $1 }
        XCTAssertEqual(SportsFormat.detailStatus(F.page(shootout)), "Full time · Penalties")
        XCTAssertEqual(SportsFormat.detailStatus(F.page(soccer.merging(["status": "live", "period": "HT", "clock": "45'"]) { $1 })),
                       "Halftime")
        XCTAssertEqual(SportsFormat.detailStatus(F.page(soccer.merging(["status": "live", "period": "H2", "clock": "67'"]) { $1 })),
                       "Second half · 67'")
        XCTAssertEqual(SportsFormat.detailStatus(F.page(["status": "scheduled", "statusDetail": "Postponed"])), "Postponed")
    }

    func testResultLine() {
        XCTAssertEqual(SportsFormat.result(F.page()), "Chicago Bears win")
        let draw = F.page(["league": "soccer-eng.1", "sport": "soccer",
                           "homeTeam": ["id": "1", "name": "Burnley", "score": "1"], "awayTeam": ["id": "2", "name": "Liverpool", "score": "1"]])
        XCTAssertEqual(SportsFormat.result(draw), "Draw")
        let pens = F.page(["league": "soccer-fifa.world", "sport": "soccer",
                           "homeTeam": ["id": "1", "name": "Argentina", "score": "3", "shootoutScore": 4, "winner": true],
                           "awayTeam": ["id": "2", "name": "France", "score": "3", "shootoutScore": 2]])
        XCTAssertEqual(SportsFormat.result(pens), "Argentina win 4–2 on penalties")
        XCTAssertNil(SportsFormat.result(F.page(["status": "live"])))
    }

    func testPregameCountdown() {
        let game = F.game(["status": "scheduled", "startTime": "2026-10-23T20:00:00Z"])
        let start = game.start
        XCTAssertNil(SportsFormat.pregameCountdown(game, now: start.addingTimeInterval(-16 * 60)))
        XCTAssertEqual(SportsFormat.pregameCountdown(game, now: start.addingTimeInterval(-(12 * 60 + 4))), "Starts in 12:04")
        XCTAssertEqual(SportsFormat.pregameCountdown(game, now: start.addingTimeInterval(30)), "Starting soon")
    }

    func testReadsGoTimestamps() {
        XCTAssertNotNil(SportsGame.date("2026-10-23T08:21:38.788755-06:00"))
        XCTAssertNotNil(SportsGame.date("2026-09-22T19:34:36.018138282-04:00"), "nanoseconds")
        XCTAssertNotNil(SportsGame.date("2026-10-23T00:15:00Z"))
    }

    func testStaleness() {
        var detail = F.nflDetail
        let updated = SportsGame.date(detail["updatedAt"] as! String)!
        let page = F.page(detail: detail)
        XCTAssertFalse(page.isStale(now: updated.addingTimeInterval(300)))
        XCTAssertTrue(page.isStale(now: updated.addingTimeInterval(700)), "10 minutes when not live")
        XCTAssertTrue(F.page(["status": "live"], detail: detail).isStale(now: updated.addingTimeInterval(150)), "2 minutes while live")
        detail["stale"] = true
        XCTAssertTrue(F.page(detail: detail).isStale(now: updated))
    }

    func testTeamComparisonRules() {
        XCTAssertNotNil(SportsTeamComparison.numbers("38%", "62"))
        XCTAssertNil(SportsTeamComparison.numbers("4-12", "2-7"), "records and ratios get no bars")
        let soccer = F.page(["league": "soccer-eng.1", "sport": "soccer"], detail: ["comparisons": [
            ["label": "Fouls", "away": "10", "home": "12"], ["label": "Corners", "away": "3", "home": "5"],
            ["label": "Possession %", "away": "40", "home": "60"]]])
        XCTAssertEqual(SportsTeamComparison.priorityRows(soccer).map(\.label), ["Possession %", "Corners", "Fouls"])
    }

    func testMatchupColours() {
        XCTAssertEqual(SportsTeamColors.hexPair(away: "000000", home: "ce1141", awayAlternate: "ffc72c"),
                       .init(away: "#ffc72c", home: "#ce1141"), "near-black gives way to the alternate")
        let pair = SportsTeamColors.hexPair(away: "c8102e", home: "ce1141")
        XCTAssertEqual(pair.away, "#c8102e")
        XCTAssertTrue(SportsTeamColors.distinct(pair.away, pair.home), "two reds become two colours")
    }
}
