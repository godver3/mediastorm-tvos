import SwiftUI
import XCTest
@testable import StrmrTV

/// Basketball and hockey tracking data (Go `SportsBasketballShot`, `SportsHockeyShot`,
/// `SportsWinProbabilityPoint`, `SportsScoreHistory`), the court geometry (Expo `basketball-court.ts`,
/// `basketball-shot-card.ts`), the charts' series (Expo `basketballElapsed`, `basketballLeadGeometry`)
/// and the basketball and hockey situations (Expo `SportsSituation` kinds `nba` / `nhl`).
final class SportsTrackingTests: XCTestCase {
    private typealias F = SportsGameFixtures

    /// The NBA final 401909093 cut down: CLE (5) at PHI (20), 106–114.
    private func nba(_ overrides: [String: Any] = [:], detail: [String: Any] = [:]) -> SportsGamePage {
        var base: [String: Any] = [
            "source": "espn", "updatedAt": "2026-10-23T08:21:38Z",
            "basketballShots": [
                ["id": "1", "teamId": "5", "x": 29, "y": 2, "made": true, "points": 2, "period": 1, "periodLabel": "Q1",
                 "clock": "11:41", "description": "Jarrett Allen makes 4-foot two point shot", "playerName": "Jarrett Allen", "jersey": "31"],
                ["id": "2", "teamId": "20", "x": 17, "y": 26, "made": false, "points": 3, "period": 1, "periodLabel": "Q1", "clock": "10:58"],
                ["id": "3", "teamId": "5", "x": "bad", "y": 1],
            ],
            "winProbability": [
                ["playId": "a", "period": 1, "periodLabel": "Q1", "clock": "12:00", "home": 0.708],
                ["playId": "b", "period": 1, "periodLabel": "Q1", "clock": "11:41", "home": 0.683],
                ["playId": "c", "period": 4, "periodLabel": "Q4", "clock": "0.0", "home": 1],
            ],
            "scoreHistory": ["eventId": "401909093", "awayTeamId": "5", "homeTeamId": "20", "complete": true, "points": [
                ["id": "1", "period": 1, "periodLabel": "1st Quarter", "clock": "12:00", "away": 0, "home": 0],
                ["id": "2", "period": 1, "periodLabel": "1st Quarter", "clock": "11:41", "away": 2, "home": 0],
                ["id": "3", "period": 2, "periodLabel": "2nd Quarter", "clock": "6:00", "away": 50, "home": 40],
                ["id": "4", "period": 4, "periodLabel": "4th Quarter", "clock": "16.9", "away": 106, "home": 114],
                ["id": "5", "period": 4, "periodLabel": "4th Quarter", "clock": "0.0", "away": 106, "home": 114],
            ]],
        ]
        base.merge(detail) { $1 }
        var json: [String: Any] = [
            "id": "401909093", "league": "nba", "sport": "basketball", "startTime": "2026-10-22T23:00:00Z", "status": "final",
            "homeTeam": ["id": "20", "name": "Philadelphia 76ers", "abbreviation": "PHI", "color": "1d428a", "alternateColor": "e01234", "score": "114"],
            "awayTeam": ["id": "5", "name": "Cleveland Cavaliers", "abbreviation": "CLE", "color": "860038", "alternateColor": "bc945c", "score": "106"],
            "detail": base,
        ]
        json.merge(overrides) { $1 }
        return SportsGamePage(game: F.decode(SportsGame.self, json), league: nil)
    }

    func testDecodesTrackingData() {
        let detail = nba().detail
        XCTAssertEqual(detail.basketballShots.count, 2, "a shot without numeric coordinates is skipped")
        XCTAssertEqual(detail.basketballShots[0].playerName, "Jarrett Allen")
        XCTAssertEqual(detail.basketballShots[0].jersey, "31")
        XCTAssertFalse(detail.basketballShots[1].made)
        XCTAssertEqual(detail.winProbability.map(\.home), [0.708, 0.683, 1])
        XCTAssertEqual(detail.scoreHistory?.points.count, 5)
        XCTAssertTrue(detail.scoreHistory?.complete == true)
        let hockey = F.decode(SportsGameDetail.self, [
            "shots": [["id": "s", "teamId": "1", "x": 58, "y": -31, "kind": "Goal", "period": "1st", "clock": "0:13"], ["id": "t"]],
            "sport": ["kind": "nhl", "strength": " Even strength ", "shotsAway": 24, "shotsHome": -1],
        ])
        XCTAssertEqual(hockey.shots.count, 1)
        XCTAssertTrue(hockey.shots[0].isGoal, "kinds compare in lower case")
        XCTAssertEqual(hockey.hockeySituation, SportsHockeySituation(strength: "Even strength", shotsAway: 24, shotsHome: nil))
        XCTAssertNil(hockey.basketballSituation, "only a situation of its own kind")
        let basketball = F.decode(SportsGameDetail.self, ["sport": ["kind": "nba", "possession": "PHI", "bonus": ""]])
        XCTAssertEqual(basketball.basketballSituation, SportsBasketballSituation(possession: "PHI", bonus: nil))
        XCTAssertNil(basketball.hockeySituation)
    }

    func testSituationsOnlyWhileLive() {
        let sport: [String: Any] = ["sport": ["kind": "nba", "possession": "cle"]]
        XCTAssertNil(nba(detail: sport).game.liveBasketballSituation, "a final has none")
        let live = nba(["status": "live"], detail: sport).game
        XCTAssertNotNil(live.liveBasketballSituation)
        XCTAssertEqual(live.side(named: "cle")?.id, "5")
        XCTAssertEqual(live.side(named: "Philadelphia 76ers")?.id, "20")
        XCTAssertNil(live.side(named: ""))
    }

    func testCourtGeometry() {
        let home = F.decode(SportsTeam.self, ["id": "2", "name": "Boston Celtics", "color": "007A33"])
        let nba = SportsCourtGeometry(league: "nba", home: home)
        XCTAssertEqual(nba.floor, .parquet)
        XCTAssertEqual(nba.laneHalf, 80)
        XCTAssertEqual(nba.threeRadius, 237.5)
        XCTAssertEqual(nba.paint, "#007a33")
        let women = SportsCourtGeometry(league: "womens-college-basketball", home: F.decode(SportsTeam.self, ["id": "1", "name": "A"]))
        XCTAssertEqual(women.laneHalf, 60)
        XCTAssertFalse(women.restricted)
        XCTAssertEqual(women.cornerDistance, (21 + 7.375 / 12) * 10, accuracy: 0.001)
        XCTAssertEqual(women.paint, "#545e65", "neutral paint without a colour")
        XCTAssertEqual(women.floor, .wood)
        let game = self.nba().game
        let shots = self.nba().detail.basketballShots
        XCTAssertEqual(SportsCourtGeometry.position(of: shots[0], in: game), CGPoint(x: 112.5, y: 330), "away attacks the left basket")
        XCTAssertEqual(SportsCourtGeometry.position(of: shots[1], in: game), CGPoint(x: 667.5, y: 370), "home attacks the right")
        var off = shots[0]
        off = SportsBasketballShot(id: off.id, teamId: off.teamId, x: 51, y: 2)
        XCTAssertNil(SportsCourtGeometry.position(of: off, in: game))
        XCTAssertNil(SportsCourtGeometry.position(of: SportsBasketballShot(id: "x", teamId: "99", x: 2, y: 2), in: game))
    }

    func testShotCardPlacement() {
        let size = CGSize(width: 900, height: 480), card = CGSize(width: 360, height: 112)
        let right = SportsCourtGeometry.cardPlacement(in: size, card: card, marker: CGPoint(x: 100, y: 100), clearance: 40, inset: 12)
        XCTAssertEqual(right, CGPoint(x: 528, y: 356), "the far corner, low for a high marker")
        let left = SportsCourtGeometry.cardPlacement(in: size, card: card, marker: CGPoint(x: 800, y: 400), clearance: 40, inset: 12)
        XCTAssertEqual(left, CGPoint(x: 12, y: 12))
        XCTAssertNil(SportsCourtGeometry.cardPlacement(in: size, card: CGSize(width: 440, height: 112), marker: .zero, clearance: 40, inset: 12),
                     "a card wider than half the court goes under it")
    }

    func testGameClock() {
        let nba = SportsGameClock(league: "nba")
        XCTAssertEqual(nba.elapsed(period: 1, clock: "12:00"), 0)
        XCTAssertEqual(nba.elapsed(period: 4, clock: "16.9") ?? 0, 2880 - 16.9, accuracy: 0.001)
        XCTAssertEqual(nba.elapsed(period: 5, clock: "5:00"), 2880, "overtimes are five minutes")
        XCTAssertNil(nba.elapsed(period: 1, clock: "13:00"))
        XCTAssertNil(nba.elapsed(period: 0, clock: "1:00"))
        XCTAssertNil(nba.elapsed(period: 1, clock: "1:75"))
        let college = SportsGameClock(league: "mens-college-basketball")
        XCTAssertEqual(college.elapsed(period: 2, clock: "20:00"), 1200)
        XCTAssertEqual(college.label(2), "H2")
        XCTAssertEqual(college.label(3), "OT1")
        XCTAssertEqual(SportsGameClock(league: "wnba").seconds, 600)
        XCTAssertNil(SportsGameClock(basketball: "nfl"))
    }

    func testWinProbabilitySeries() throws {
        let series = try XCTUnwrap(SportsWinProbabilitySeries(page: nba()))
        XCTAssertEqual(series.points.map(\.elapsed), [0, 19, 2880])
        XCTAssertEqual(series.latest.home, 1)
        XCTAssertEqual(series.periods.map(\.label), ["Q1", "Q2", "Q3", "Q4"])
        let backwards: [String: Any] = ["winProbability": [["period": 2, "clock": "1:00", "home": 0.5], ["period": 1, "clock": "1:00", "home": 0.5]]]
        XCTAssertNil(SportsWinProbabilitySeries(page: nba(detail: backwards)), "out of order")
        let range: [String: Any] = ["winProbability": [["period": 1, "clock": "1:00", "home": 0.5], ["period": 1, "clock": "0:30", "home": 1.2]]]
        XCTAssertNil(SportsWinProbabilitySeries(page: nba(detail: range)))
        XCTAssertNil(SportsWinProbabilitySeries(page: nba(detail: ["winProbability": [["period": 1, "clock": "1:00", "home": 0.5]]])))
    }

    func testLeadSeries() throws {
        let series = try XCTUnwrap(SportsLeadSeries(page: nba()))
        XCTAssertEqual(series.points.map(\.lead), [0, 2, 10, -8, -8], "first, last and every change")
        XCTAssertEqual(series.extent, 10)
        XCTAssertEqual(series.latest, -8)
        let crossings = series.crossings
        XCTAssertEqual(crossings.count, 6, "a zero point where the lead changes sides")
        XCTAssertEqual(crossings[3].lead, 0)
        XCTAssertEqual(series.runs.map(\.away), [true, false])
        XCTAssertNil(SportsLeadSeries(page: nba(["homeTeam": ["id": "20", "name": "Philadelphia 76ers", "score": "115"]])),
                     "the history must end on the scoreboard's score")
        XCTAssertNil(SportsLeadSeries(page: nba(["id": "other"])), "another game's history")
        XCTAssertNil(SportsLeadSeries(page: nba(["league": "nfl"])))
        XCTAssertNil(SportsLeadSeries(page: nba(["status": "scheduled"])))
    }

    func testChartColoursReadOnTheDarkChart() {
        let away = F.decode(SportsTeam.self, ["id": "1", "name": "A", "color": "0c2340", "alternateColor": "a2aaad"])
        let home = F.decode(SportsTeam.self, ["id": "2", "name": "B", "color": "000000", "alternateColor": "000000"])
        let pair = SportsTeamColors.chartPair(away: away, home: home)
        XCTAssertEqual(pair.away, "#a2aaad", "navy is too dark: its alternate")
        XCTAssertNotEqual(pair.home, "#000000")
    }

    func testHockeyEventsAndBadges() {
        let play = { (title: String, scoring: Bool) in SportsPlay(id: title, title: title, scoring: scoring) }
        XCTAssertEqual(SportsHockeyEvent(play("Face Off", false)), .faceoff)
        XCTAssertEqual(SportsHockeyEvent(play("Blocked", false)), .blocked)
        XCTAssertEqual(SportsHockeyEvent(play("Goal", true)), .goal)
        XCTAssertEqual(SportsHockeyEvent(play("Tripping", false)), .other)
        XCTAssertEqual(SportsHockeyGoalBadge(play("Power-Play Goal", true))?.text, "PP · Power-play goal")
        XCTAssertEqual(SportsHockeyGoalBadge(play("Shorthanded Goal", true))?.short, "SH")
        XCTAssertEqual(SportsHockeyGoalBadge(play("Empty Net Goal", true))?.short, "EN")
        XCTAssertNil(SportsHockeyGoalBadge(play("Goal", true)))
        XCTAssertNil(SportsHockeyGoalBadge(SportsPlay(id: "s", title: "Power Play Goal", shootout: true)))
    }
}
