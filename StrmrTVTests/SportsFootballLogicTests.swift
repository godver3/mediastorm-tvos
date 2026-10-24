import XCTest
@testable import StrmrTV

/// American football's field logic (Expo `football-presentation.ts`, `sports-detail-geometry.ts`,
/// `sports-drive-validity.ts` and the replay's play classification): spots turned to the
/// offense's own goal, drive paths, summaries and results, the live field's state, how a drive's
/// plays read, and the drive explorer's choice.
final class SportsFootballLogicTests: XCTestCase {
    private typealias F = SportsGameFixtures
    private typealias S = SportsSituationFixtures

    private func drive(_ id: String, team: String = "17", start: Double? = 25, end: Double? = 60, result: String = "PUNT",
                       current: Bool = false, description: String = "", plays: [SportsFootballPlay] = []) -> SportsFootballDrive {
        SportsFootballDrive(id: id, teamId: team, period: "Q4", result: result, description: description, current: current,
                            start: start, end: end, plays: plays)
    }

    private func play(_ id: String, type: String = "Rush", typeId: String? = nil, down: Int? = 1, distance: Double? = 10,
                      yards: Double? = nil, team: String? = "17", start: Double? = 25, end: Double? = 32,
                      scoring: Bool? = false, description: String = "") -> SportsFootballPlay {
        SportsFootballPlay(id: id, type: type, description: description, clock: "1:00", period: "Q4", typeId: typeId, wallclock: nil,
                           down: down, distance: distance, yards: yards, possessionTeamId: team, start: start, end: end, scoring: scoring)
    }

    func testYards() {
        let game = S.nflLive().game
        XCTAssertEqual(SportsFootballYards.own(88, for: game.awayTeam, in: game), 88)
        XCTAssertEqual(SportsFootballYards.own(88, for: game.homeTeam, in: game), 12)
        XCTAssertEqual(SportsFootballYards.label(27, in: game), "NE 27")
        XCTAssertEqual(SportsFootballYards.label(88, in: game), "CHI 12")
        XCTAssertEqual(SportsFootballYards.label(50, in: game), "50")
        XCTAssertFalse(SportsFootballYards.isValid(101))
        XCTAssertFalse(SportsFootballYards.isValid(.nan))
        XCTAssertFalse(SportsFootballYards.isValid(nil))
    }

    func testReliableDrivePath() {
        XCTAssertTrue(drive("1").hasReliablePath)
        XCTAssertFalse(drive("2", start: 47, end: 47).hasReliablePath, "equal ends aren't movement")
        XCTAssertFalse(drive("3", start: nil).hasReliablePath)
        XCTAssertFalse(drive("4", end: 120).hasReliablePath)
        var unknown = drive("5")
        unknown.startKnown = false
        XCTAssertFalse(unknown.hasReliablePath, "the feed says it couldn't place the start")
        XCTAssertNil(unknown.knownStart)
    }

    func testDriveSummaryAndFigures() {
        let summary = SportsDriveSummary(" 1 play, -1 yard, 0:37 ")
        XCTAssertEqual(summary?.plays, 1)
        XCTAssertEqual(summary?.yards, -1)
        XCTAssertEqual(summary?.duration, "0:37")
        XCTAssertNil(SportsDriveSummary("Drive ended on downs"))
        var withFields = drive("1", description: "6 plays, 23 yards, 3:30")
        XCTAssertEqual(withFields.statsLine, "6 plays · 23 yards · 3:30", "from the summary")
        withFields.playCount = 7
        withFields.yards = 1
        withFields.elapsed = "4:01"
        XCTAssertEqual(withFields.statsLine, "7 plays · 1 yard · 4:01", "the feed's own figures first")
        XCTAssertNil(drive("2").statsLine)
    }

    func testDriveResults() {
        let result = { (raw: String) in
            let made = SportsDriveResult(self.drive("1", result: raw), possession: nil)
            return "\(made.text)|\(made.scoring)|\(made.current)"
        }
        XCTAssertEqual(result("TD"), "Touchdown|true|false")
        XCTAssertEqual(result("FG"), "Field goal|true|false")
        XCTAssertEqual(result("Safety"), "Safety|true|false")
        XCTAssertEqual(result("PUNT"), "PUNT|false|false")
        XCTAssertEqual(result(" "), "Result unavailable|false|false")
        let live = S.nflLive(detail: ["footballDrives": [["id": "9", "teamId": "17", "start": 25, "end": 88, "current": true, "result": ""]]])
        let current = SportsDriveResult(live.detail.footballDrives[0], possession: SportsFootballPossession(page: live))
        XCTAssertEqual(current.text, "In progress")
        XCTAssertTrue(current.current)
        XCTAssertFalse(current.scoring)
        let stale = S.nflLive(detail: ["footballDrives": [["id": "9", "teamId": "17", "current": true, "result": "TD"]]], stale: true)
        XCTAssertFalse(SportsDriveResult(stale.detail.footballDrives[0], possession: SportsFootballPossession(page: stale)).current,
                       "old data never shows a drive in progress")
        let other = S.nflLive(detail: ["footballDrives": [["id": "9", "teamId": "3", "current": true, "result": ""]]])
        XCTAssertFalse(SportsDriveResult(other.detail.footballDrives[0], possession: SportsFootballPossession(page: other)).current,
                       "only the side with the ball has a drive in progress")
    }

    func testGeometryFromTheSituation() {
        let game = S.nflLive().game
        let geometry = SportsFootballGeometry(situation: SportsFootballSituation(possession: "NE", downDistance: "3rd & 4", fieldPosition: "CHI 12"),
                                              game: game)
        XCTAssertEqual(geometry?.ball, 88)
        XCTAssertEqual(geometry?.direction, 1)
        XCTAssertEqual(geometry?.target, 92)
        let home = SportsFootballGeometry(situation: SportsFootballSituation(possession: "CHI", downDistance: "1st and 10", fieldPosition: "Ball on CHI 25"),
                                          game: game)
        XCTAssertEqual(home?.ball, 75)
        XCTAssertEqual(home?.target, 65, "the home side attacks the away goal")
        let goal = SportsFootballGeometry(situation: SportsFootballSituation(possession: "NE", downDistance: "1st & Goal", fieldPosition: "CHI 5"),
                                          game: game)
        XCTAssertEqual(goal?.target, 100)
        XCTAssertEqual(SportsFootballGeometry(situation: SportsFootballSituation(possession: "NE", fieldPosition: "Midfield"), game: game)?.ball, 50)
        XCTAssertNil(SportsFootballGeometry(situation: SportsFootballSituation(possession: "NE", fieldPosition: "DAL 20"), game: game))
        XCTAssertNil(SportsFootballGeometry(situation: SportsFootballSituation(possession: "NE", fieldPosition: "CHI 60"), game: game))
        XCTAssertNil(SportsFootballGeometry(situation: SportsFootballSituation(possession: "XYZ", fieldPosition: "CHI 12"), game: game))
    }

    func testPossessionWhileLive() throws {
        let plays: [[String: Any]] = [["id": "p1", "type": "Rush", "description": "Run", "clock": "0:47", "period": "Q4", "start": 82, "end": 86],
                                      ["id": "p2", "type": "Rush", "description": "Run", "clock": "0:43", "period": "Q4", "start": 86, "end": 88]]
        let page = S.nflLive(detail: ["footballDrives": [["id": "8", "teamId": "3", "current": false],
                                                         ["id": "9", "teamId": "17", "start": 25, "end": 88, "current": true, "plays": plays]]])
        let possession = try XCTUnwrap(SportsFootballPossession(page: page))
        XCTAssertNil(possession.pause)
        XCTAssertTrue(possession.isLive)
        XCTAssertEqual(possession.offense.id, "17")
        XCTAssertEqual(possession.opponent.id, "3")
        XCTAssertEqual(possession.ball, 88)
        XCTAssertEqual(possession.target, 92)
        XCTAssertEqual(possession.currentDrive?.id, "9")
        XCTAssertEqual(possession.plays.map(\.id), ["p1", "p2"])
        let home = try XCTUnwrap(SportsFootballPossession(page: S.nflLive(["footballSituation": ["possession": "CHI", "downDistance": "2nd & 6",
                                                                                                   "fieldPosition": "CHI 30"]])))
        XCTAssertEqual(home.ball, 30, "turned to the home side's own goal")
        XCTAssertEqual(home.target, 36)
    }

    func testPossessionPauses() throws {
        let pause = { (page: SportsGamePage) in SportsFootballPossession(page: page)?.pause }
        XCTAssertEqual(pause(F.page(detail: F.nflDetail))?.title, "Final", "a final says so, old data or not")
        XCTAssertEqual(pause(S.nflLive(["status": "scheduled", "statusDetail": "Scheduled"]))?.title, "Kickoff upcoming")
        XCTAssertEqual(pause(S.nflLive(stale: true)), SportsFootballPause(kind: .waiting, title: "Updates delayed",
                                                                         subtitle: "Waiting for the latest field position"))
        let noSpot = try XCTUnwrap(SportsFootballPossession(page: S.nflLive(["footballSituation": NSNull()])))
        XCTAssertEqual(noSpot.pause?.title, "Waiting for field position")
        XCTAssertEqual(noSpot.offense.id, "17", "the away side, so both end zones still show")
        XCTAssertEqual(pause(S.nflLive(["statusDetail": "Halftime", "period": "Q2", "clock": "0:00"])),
                       SportsFootballPause(kind: .halftime, title: "Halftime"))
        XCTAssertEqual(pause(S.nflLive(["statusDetail": "Halftime · 12:00 remaining"]))?.subtitle, "12:00 remaining")
        XCTAssertEqual(pause(S.nflLive(["statusDetail": "Timeout by NE"]))?.title, "Timeout · New England Patriots")
        XCTAssertEqual(pause(S.nflLive(["statusDetail": "Timeout"]))?.title, "Timeout", "no side named")
        XCTAssertEqual(pause(S.nflLive(["statusDetail": "Official timeout"]))?.title, "Official timeout")
        let timeoutPlay = S.nflLive(detail: ["plays": [["id": "t", "periodLabel": "Q4", "clock": "0:41", "title": "Timeout",
                                                        "description": "Timeout #2 by CHI at 00:41."]]])
        XCTAssertEqual(pause(timeoutPlay)?.title, "Timeout · Chicago Bears")
        let touchdown = S.nflLive(detail: ["plays": [["id": "s", "periodLabel": "Q4", "clock": "0:41", "title": "Passing Touchdown",
                                                      "teamId": "17", "scoring": true]]])
        XCTAssertEqual(pause(touchdown), SportsFootballPause(kind: .score, title: "Touchdown", subtitle: "New England Patriots · 6 points"))
        XCTAssertNil(SportsFootballPossession(page: S.mlbLive()), "not a football league")
    }

    func testPlayInfo() {
        let game = S.nflLive().game
        let offense = game.awayTeam
        let pass = SportsFootballPlayInfo(play("1", type: "Pass Reception", typeId: "24", down: 2, distance: 7, yards: 14, start: 28, end: 42),
                                          offense: offense, game: game)
        XCTAssertEqual(pass.kind, .pass)
        XCTAssertEqual(pass.down, "2nd & 7")
        XCTAssertEqual(pass.spot, "NE 28")
        XCTAssertEqual(pass.result, "14-yard completion · First down")
        XCTAssertEqual(pass.type, "Pass")
        XCTAssertEqual(pass.movement, "+14 YD")
        let goalToGo = SportsFootballPlayInfo(play("2", down: 1, distance: 8, yards: 2, start: 92, end: 94), offense: offense, game: game)
        XCTAssertEqual(goalToGo.down, "1st & Goal")
        XCTAssertEqual(goalToGo.result, "2-yard run")
        let homeLoss = SportsFootballPlayInfo(play("3", type: "Sack", down: 3, distance: 9, team: "3", start: 70, end: 75),
                                              offense: game.homeTeam, game: game)
        XCTAssertEqual(homeLoss.kind, .sack)
        XCTAssertEqual(homeLoss.movement, "−5 YD", "measured toward the home side's goal")
        XCTAssertEqual(SportsFootballPlayInfo(play("4", type: "Pass Incompletion", typeId: "3"), offense: offense, game: game).result,
                       "Incomplete pass")
        let kickoff = SportsFootballPlayInfo(play("5", type: "Kickoff", typeId: "53", down: 1, distance: 10, start: nil, end: nil),
                                             offense: offense, game: game)
        XCTAssertNil(kickoff.down, "a kickoff has no down, whatever the feed says")
        XCTAssertEqual(kickoff.result, "Kickoff")
        XCTAssertEqual(kickoff.movement, "—")
        XCTAssertEqual(SportsFootballPlayInfo.kind(play("6", type: "Pass Reception", description: "… PENALTY on CHI - No Play.")), .penalty)
        XCTAssertEqual(SportsFootballPlayInfo.kind(play("7", type: "Fumble Recovery (Opponent)")), .turnover)
        XCTAssertEqual(SportsFootballPlayInfo.kind(play("8", type: "Field Goal Good")), .kick)
        XCTAssertFalse(SportsFootballPlayInfo.isFieldPlay(play("9", type: "Kickoff")))
        XCTAssertFalse(SportsFootballPlayInfo.isFieldPlay(play("10", type: "Official Timeout")))
        XCTAssertTrue(SportsFootballPlayInfo.isFieldPlay(play("11", type: "Penalty")))
    }

    func testRibbonLabelPlacement() {
        XCTAssertEqual(SportsRibbonLabel(start: 20, end: 60, text: "+40 YD").inside, true)
        let short = SportsRibbonLabel(start: 40, end: 44, text: "+4 YD")
        XCTAssertFalse(short.inside)
        XCTAssertEqual(short.anchor, .trailing, "beside the tail, toward the offense's own goal")
        let crowded = SportsRibbonLabel(start: 1, end: 4, text: "+3 YD")
        XCTAssertTrue(crowded.above, "no room behind the tail")
        XCTAssertTrue(SportsRibbonLabel(start: nil, end: 4, text: "—").above)
    }

    func testDriveExplorerChoice() {
        let drives = [drive("1"), drive("2", team: "3"), drive("3"), drive("4", team: "3", current: true)]
        var explorer = SportsDriveExplorer(drives: drives)
        XCTAssertEqual(explorer.listed.map(\.id), ["4", "3", "2", "1"], "newest first")
        XCTAssertEqual(explorer.selected?.id, "4", "the newest without a choice")
        explorer.currentID = "3"
        XCTAssertEqual(explorer.selected?.id, "3", "the drive in progress before the newest")
        explorer.chosenID = "2"
        XCTAssertEqual(explorer.selected?.id, "2")
        explorer.teamID = "17"
        XCTAssertEqual(explorer.listed.map(\.id), ["3", "1"])
        XCTAssertEqual(explorer.selected?.id, "3", "the choice isn't listed for this side")
        explorer.teamID = nil
        XCTAssertEqual(explorer.selected?.id, "2", "and comes back with both sides")
        XCTAssertEqual(explorer.number(of: drives[2]), 3, "numbered in game order")
        explorer.teamID = "99"
        XCTAssertNil(explorer.selected)
    }

    func testDriveLanes() {
        let plays = [play("k", type: "Kickoff", start: 65, end: 25), play("1"), play("2", start: nil),
                     play("t", type: "Timeout"), play("3", start: 32, end: 40)]
        XCTAssertEqual(SportsDriveExplorer.lanes(plays).map(\.id), ["1", "3"])
        XCTAssertEqual(SportsDriveExplorer.lanes(plays, limit: 1).map(\.id), ["3"], "the latest")
    }
}
