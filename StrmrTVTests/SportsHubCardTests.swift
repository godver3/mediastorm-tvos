import XCTest
@testable import StrmrTV

/// The hub's cards and rows (Expo `SportsHubShowcase`, `sports-card-status.ts`,
/// `useSportsScoreChange`, `sports-team-order.ts`): countdowns, live context lines, the score-change
/// cue, stale leagues and an order that holds across refreshes.
final class SportsHubCardTests: XCTestCase {
    private typealias F = SportsGameFixtures
    private typealias S = SportsSituationFixtures

    private func game(_ id: String, start: String = "2026-10-23T19:00:00Z", status: String = "final") -> SportsGame {
        F.game(["id": id, "startTime": start, "status": status, "statusDetail": status == "final" ? "Final" : ""])
    }

    func testCountdown() {
        let start = Date(timeIntervalSince1970: 100_000)
        let before = { (minutes: Double) in start.addingTimeInterval(-minutes * 60) }
        XCTAssertEqual(SportsFormat.countdown(to: start, now: before(24.5)), "Starts in 25 min", "minutes round up")
        XCTAssertEqual(SportsFormat.countdown(to: start, now: before(125)), "Starts in 2h 5m")
        XCTAssertEqual(SportsFormat.countdown(to: start, now: before(120)), "Starts in 2h")
        XCTAssertEqual(SportsFormat.countdown(to: start, now: before(1440)), "Starts in 1 day")
        XCTAssertEqual(SportsFormat.countdown(to: start, now: before(1441)), "Starts in 2 days")
        XCTAssertEqual(SportsFormat.countdown(to: start, now: start), "Awaiting start", "never live on the clock alone")
        XCTAssertEqual(SportsFormat.countdown(to: nil, now: start), "Upcoming")
        let scheduled = game("s", start: "2026-10-23T19:00:00Z", status: "scheduled")
        let line = SportsFormat.statusLine(scheduled, spoilers: false, now: scheduled.start.addingTimeInterval(-25 * 60))
        XCTAssertTrue(line.hasSuffix(" · Starts in 25 min"), line)
    }

    func testBaseballFooter() {
        let footer = SportsCardFooter.make(S.mlbLive().game, kind: .baseball, spoilers: false)
        XCTAssertEqual(footer?.text, "3–2 count · 2 outs")
        XCTAssertEqual(footer?.bases, [true, false, true])
        XCTAssertNil(SportsCardFooter.make(S.mlbLive().game, kind: .baseball, spoilers: true), "hidden with scores")
        XCTAssertNil(SportsCardFooter.make(S.mlbLive(["statusDetail": "Middle 7th"]).game, kind: .baseball, spoilers: false))
    }

    func testFootballAndReportedFooters() {
        let football = SportsCardFooter.make(S.nflLive().game, kind: .football, spoilers: false)
        XCTAssertEqual(football?.text, "NE · 3rd & 4 · Ball at CHI 12")
        XCTAssertEqual(football?.symbol, "football.fill")
        let hockey = F.game(["league": "nhl", "status": "live", "statusDetail": "Power play - BOS", "period": "P2", "clock": "4:00"])
        XCTAssertEqual(SportsCardFooter.make(hockey, kind: .hockey, spoilers: false),
                       SportsCardFooter(symbol: "hockey.puck.fill", text: "Power play - BOS"))
        let clock = F.game(["league": "nba", "status": "live", "statusDetail": "7:21 - 3rd Quarter"])
        XCTAssertNil(SportsCardFooter.make(clock, kind: .basketball, spoilers: false), "a plain clock isn't context")
        XCTAssertNil(SportsCardFooter.make(F.game(), kind: .football, spoilers: false), "not after the game")
    }

    func testScoreChange() {
        let live = F.game(["status": "live", "statusDetail": "Q4"])
        let key = SportsScoreChange.key(live, spoilers: false)
        XCTAssertEqual(key, "24|30")
        XCTAssertNil(SportsScoreChange.key(live, spoilers: true))
        XCTAssertNil(SportsScoreChange.key(F.game(), spoilers: false), "finals don't light up")
        XCTAssertTrue(SportsScoreChange.changed(from: "24|30", to: "24|33"))
        XCTAssertFalse(SportsScoreChange.changed(from: nil, to: "24|30"), "never on the first load")
        XCTAssertFalse(SportsScoreChange.changed(from: "24|30", to: nil), "nor when scores are hidden")
        XCTAssertFalse(SportsScoreChange.changed(from: "24|30", to: "24|30"))
    }

    func testOrderHoldsAcrossRefreshes() {
        var ordering = SportsHubOrdering()
        let a = game("b-game"), b = game("a-game"), c = game("c-game", start: "2026-10-23T18:00:00Z")
        ordering.record([a, b, c])
        let rank = { (_: SportsGame) in 0 }
        XCTAssertEqual(ordering.ordered([a, b, c], in: .live, rank: rank).map(\.id), ["c-game", "a-game", "b-game"],
                       "by start, then id")
        XCTAssertEqual(ordering.ordered([b, c, a].reversed(), in: .live, rank: rank).map(\.id), ["c-game", "a-game", "b-game"],
                       "the feed's order doesn't matter")
        XCTAssertEqual(ordering.ordered([a, b, c], in: .results, rank: rank).map(\.id), ["b-game", "a-game", "c-game"], "latest first")
        // A game whose start moves keeps its place in live and results, and moves among upcoming games.
        let moved = game("c-game", start: "2026-10-23T20:00:00Z")
        ordering.record([moved])
        XCTAssertEqual(ordering.ordered([a, b, moved], in: .live, rank: rank).map(\.id), ["c-game", "a-game", "b-game"])
        XCTAssertEqual(ordering.ordered([a, b, moved], in: .upcoming, rank: rank).map(\.id), ["a-game", "b-game", "c-game"])
        let late = game("0-new", start: "2026-10-23T17:00:00Z")
        ordering.record([late, a, b, moved])
        XCTAssertEqual(ordering.ordered([late, a, b, moved], in: .live, rank: rank).last?.id, "0-new", "a new game goes last")
        XCTAssertEqual(ordering.ordered([a, b, late], in: .live, rank: { $0.id == "b-game" ? 0 : 1 }).first?.id, "b-game",
                       "followed competitions lead")
    }

    func testSideOrder() {
        XCTAssertFalse(SportsKind.kind(leagueID: "nba").awayFirst, "home first for team sports")
        XCTAssertTrue(SportsKind.kind(leagueID: "atp").awayFirst)
        XCTAssertTrue(SportsKind.kind(leagueID: "ufc").awayFirst)
        XCTAssertTrue(SportsKind.kind(leagueID: "pga").awayFirst)
    }

    func testStaleLeagues() {
        let json: [String: Any] = [
            "games": [["id": "1", "league": "nhl", "startTime": "2026-10-23T19:00:00Z", "status": "live",
                       "homeTeam": ["id": "h", "name": "H"], "awayTeam": ["id": "a", "name": "A"]]],
            "updatedAt": "2026-10-23T19:00:00Z", "stale": false,
            "leagues": [["league": "nhl", "stale": true, "unavailable": false], ["league": "nba", "stale": false], ["bad": 1]],
        ]
        let board = F.decode(SportsScoreboard.self, json)
        XCTAssertEqual(board.leagues.count, 2)
        XCTAssertEqual(board.staleLeagues, ["nhl"])
        var whole = json
        whole["stale"] = true
        whole["leagues"] = [] as [Any]
        XCTAssertEqual(F.decode(SportsScoreboard.self, whole).staleLeagues, ["nhl"], "a stale board flags every league on it")
        whole["updatedAt"] = nil
        XCTAssertEqual(F.decode(SportsScoreboard.self, whole).staleLeagues, [], "only a board that says when it was built")
        XCTAssertTrue(F.decode(SportsScoreboard.self, ["games": NSNull()]).games.isEmpty)
    }
}
