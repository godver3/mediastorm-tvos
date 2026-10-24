import XCTest
@testable import StrmrTV

/// MLB's at-bat and line score (Expo `sports-baseball-state.ts`, `SportsPeriodBreakdown` for MLB)
/// and the scoreboard's live situation for football and baseball (Expo
/// `SportsEditorialScoreboard`, `BaseballSituationLine`), never shown with scores hidden.
final class SportsBaseballLogicTests: XCTestCase {
    private typealias F = SportsGameFixtures
    private typealias S = SportsSituationFixtures

    private func live(_ situation: [String: Any], _ overrides: [String: Any] = [:]) -> SportsGamePage {
        var json = S.mlbJSON(overrides)
        let full = S.situation(situation)
        json["liveSituation"] = full
        var detail = json["detail"] as? [String: Any] ?? [:]
        detail["sport"] = full
        json["detail"] = detail
        return SportsGamePage(game: F.decode(SportsGame.self, json), league: nil)
    }

    func testActiveAtBat() {
        let state = SportsBaseballState(game: S.mlbLive().game)
        XCTAssertTrue(state.active)
        XCTAssertEqual(state.inning, 7)
        XCTAssertEqual(state.batting?.id, "15", "the away side bats in the top")
        XCTAssertEqual(state.pitching?.id, "22")
        XCTAssertEqual(state.count, "Count 3–2")
        XCTAssertEqual(state.outs, "2 outs")
        XCTAssertEqual(state.scoreboardLine(stale: false), "2 outs · Count 3–2")
        XCTAssertEqual(state.scoreboardLine(stale: true), "Last reported · 2 outs · Count 3–2")
        let bottom = SportsBaseballState(game: live(["inning": "Bot 8th", "outs": 1], ["period": "Bot 8th"]).game)
        XCTAssertEqual(bottom.batting?.id, "22")
        XCTAssertEqual(bottom.outs, "1 out")
    }

    func testNoAtBatBetweenHalfInnings() {
        let middle = SportsBaseballState(game: live(["inning": "Middle 7th"], ["statusDetail": "Middle 7th", "period": "Middle 7th"]).game)
        XCTAssertFalse(middle.active)
        XCTAssertEqual(middle.status, "Middle 7th")
        XCTAssertNil(middle.batting)
        XCTAssertNil(middle.count)
        XCTAssertNil(middle.scoreboardLine(stale: false))
        let third = SportsBaseballState(game: live(["outs": 3]).game)
        XCTAssertFalse(third.active)
        XCTAssertEqual(third.status, "Half-inning complete")
        let delayed = SportsBaseballState(game: live(["inning": "Delayed, Top 1st"], ["statusDetail": "Delayed, Top 1st"]).game)
        XCTAssertFalse(delayed.active, "a delay isn't live")
        XCTAssertNil(delayed.situation, "no situation is read while delayed")
        XCTAssertEqual(delayed.status, "Delayed, Top 1st")
        let change = SportsBaseballState(game: live(["inning": "Top 7th"], ["statusDetail": "Pitching Change"]).game)
        XCTAssertFalse(change.active)
        XCTAssertEqual(change.status, "Pitching Change")
        XCTAssertFalse(SportsBaseballState(game: S.mlbLive(["status": "final", "statusDetail": "Final"]).game).active)
    }

    @MainActor func testOddCountsAreLeftOut() {
        let state = SportsBaseballState(game: live(["balls": 4, "strikes": 2, "outs": 5]).game)
        XCTAssertTrue(state.active)
        XCTAssertNil(state.count, "four balls isn't a count")
        XCTAssertNil(state.outs)
        XCTAssertEqual(SportsBaseballCount.rows(state.situation).map(\.label), ["Strikes"])
    }

    func testLineScore() {
        let score = SportsBaseballLineScore(page: S.mlbLive())
        XCTAssertEqual(score.innings.count, 9, "at least nine")
        XCTAssertEqual(score.innings[6], .init(number: 7, away: "0", home: "–"))
        XCTAssertEqual(score.innings[8], .init(number: 9, away: "–", home: "–"))
        XCTAssertEqual(score.current, 7)
        XCTAssertEqual(score.totals, [.init(label: "R", away: "0", home: "0"), .init(label: "H", away: "2", home: "3"),
                                      .init(label: "E", away: "0", home: "1")])
        var json = S.mlbJSON(["status": "final", "statusDetail": "Final", "liveSituation": NSNull()])
        var detail = json["detail"] as? [String: Any] ?? [:]
        detail["periods"] = (1...11).map { ["label": "\($0)", "away": "0", "home": $0 == 11 ? "1" : "0"] }
        detail["comparisons"] = []
        json["detail"] = detail
        let extras = SportsBaseballLineScore(page: SportsGamePage(game: F.decode(SportsGame.self, json), league: nil))
        XCTAssertEqual(extras.innings.count, 11, "extra innings")
        XCTAssertNil(extras.current)
        XCTAssertEqual(extras.totals.last, .init(label: "E", away: "–", home: "–"))
    }

    func testHeaderSituation() {
        let football = SportsHeaderSituation(page: S.nflLive(), spoilers: false)
        XCTAssertEqual(football.lines, ["3rd & 4", "Ball at CHI 12"])
        XCTAssertTrue(football.hasBall(S.nflLive().game.awayTeam))
        XCTAssertFalse(football.hasBall(S.nflLive().game.homeTeam))
        let baseball = SportsHeaderSituation(page: S.mlbLive(), spoilers: false)
        XCTAssertEqual(baseball.lines, ["2 outs · Count 3–2"])
        XCTAssertEqual(baseball.baseball?.situation?.occupiedBases, [true, false, true])
        for page in [S.nflLive(), S.mlbLive()] {
            let hidden = SportsHeaderSituation(page: page, spoilers: true)
            XCTAssertNil(hidden.football, "nothing of the live situation with scores hidden")
            XCTAssertNil(hidden.baseball)
            XCTAssertNil(hidden.offense)
            XCTAssertEqual(hidden.lines, [])
        }
        XCTAssertEqual(SportsHeaderSituation(page: F.page(detail: F.nflDetail), spoilers: false).lines, [], "not live")
        XCTAssertEqual(SportsHeaderSituation(page: live(["inning": "Middle 7th"], ["period": "Middle 7th"]), spoilers: false).lines, [],
                       "no at-bat under way")
    }
}
