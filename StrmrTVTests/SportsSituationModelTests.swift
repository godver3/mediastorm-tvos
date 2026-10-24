import XCTest
@testable import StrmrTV

/// The live situation a game carries (Go `SportsFootballSituation` / `SportsMLBSituation`, Expo
/// `SportsSituation` and `sports-backend-source.ts`): football's possession, down and distance on
/// NFL and college games, MLB's at-bat on the game and in its detail, read only while live.
final class SportsSituationModelTests: XCTestCase {
    private typealias F = SportsGameFixtures
    private typealias S = SportsSituationFixtures

    func testDecodesTheFootballSituation() {
        let game = S.nflLive().game
        let situation = game.footballSituation
        XCTAssertEqual(situation?.possession, "NE", "trimmed")
        XCTAssertEqual(situation?.downDistance, "3rd & 4")
        XCTAssertEqual(situation?.fieldPosition, "CHI 12")
        XCTAssertEqual(situation?.ballAt, "Ball at CHI 12")
        XCTAssertEqual(situation?.offense(in: game)?.id, "17")
        XCTAssertEqual(situation.flatMap { $0.timeouts(for: game.awayTeam, in: game) }, 0)
        XCTAssertEqual(situation.flatMap { $0.timeouts(for: game.homeTeam, in: game) }, 1)
        XCTAssertEqual(game.liveFootballSituation, situation)
    }

    func testFootballSituationOnlyWhileLiveForFootballLeagues() {
        XCTAssertNil(S.nflLive(["status": "final", "statusDetail": "Final"]).game.liveFootballSituation)
        XCTAssertNil(S.nflLive(["league": "espn:football:ufl"]).game.liveFootballSituation)
        XCTAssertNotNil(S.nflLive(["league": "college-football"]).game.liveFootballSituation)
    }

    func testOffenseMatchesIdAbbreviationOrName() {
        let game = S.nflLive().game
        for possession in ["3", "chi", "Chicago Bears"] {
            let situation = SportsFootballSituation(possession: possession)
            XCTAssertEqual(situation.offense(in: game)?.id, "3", possession)
        }
        XCTAssertNil(SportsFootballSituation(possession: "").offense(in: game))
        XCTAssertNil(SportsFootballSituation(possession: "DAL").offense(in: game))
        XCTAssertNil(SportsFootballSituation(awayTimeouts: 5).timeouts(for: game.awayTeam, in: game), "out of range")
    }

    func testDecodesTheBaseballSituationLeniently() {
        let game = S.mlbLive().game
        XCTAssertEqual(game.liveSituation?.inning, "Top 7th")
        XCTAssertNil(game.liveSituation?.batterId, "the scoreboard's carries no ids")
        let detail = game.detail?.sport
        XCTAssertEqual(detail?.batterId, "33783")
        XCTAssertEqual(detail?.pitcherId, "39667", "a number reads as text")
        XCTAssertEqual(detail?.pitcherPitchCount, 94)
        XCTAssertEqual(game.liveBaseballSituation, detail, "the detail's, with ids, comes first")
        var noDetail = S.mlbJSON()
        noDetail["detail"] = nil
        XCTAssertEqual(F.decode(SportsGame.self, noDetail).liveBaseballSituation?.batter, "Ozzie Albies")
        let odd = F.decode(SportsBaseballSituation.self, #"{"inning": "Top 1st", "balls": "three", "bases": "", "batter": null}"#)
        XCTAssertNil(odd.balls)
        XCTAssertNil(odd.bases)
        XCTAssertNil(odd.batter)
    }

    func testBaseballSituationOnlyWhileLive() {
        XCTAssertNil(S.mlbLive(["status": "final", "statusDetail": "Final"]).game.liveBaseballSituation)
        XCTAssertNil(S.mlbLive(["statusDetail": "Delayed, Top 1st"]).game.liveBaseballSituation, "a delay isn't live")
    }

    func testPeriodLabel() {
        XCTAssertEqual(S.mlbLive(["period": "Top 7"]).game.periodLabel, "Top 7th", "live MLB: the at-bat's half-inning")
        XCTAssertEqual(S.nflLive().game.periodLabel, "Q4")
        XCTAssertNil(S.nflLive(["status": "scheduled", "statusDetail": "Scheduled"]).game.periodLabel)
        XCTAssertEqual(SportsFormat.detailStatus(S.mlbLive(["period": "Top 7"])), "Top 7th")
    }

    func testOccupiedBases() {
        let bases = { (label: String?) in SportsBaseballSituation(bases: label).occupiedBases }
        XCTAssertEqual(bases("Bases empty"), [false, false, false])
        XCTAssertEqual(bases("Runners on 1st & 3rd"), [true, false, true])
        XCTAssertEqual(bases("Runner on 2nd"), [false, true, false])
        XCTAssertEqual(bases("On 1st & 2nd & 3rd"), [true, true, true])
        XCTAssertEqual(bases("2nd"), [false, true, false])
        XCTAssertNil(bases("Bases loaded"), "only the plain labels")
        XCTAssertNil(bases(nil))
    }

    func testDriveKnownEnds() {
        let detail = F.decode(SportsGameDetail.self, """
        {"footballDrives": [{"id": "1", "teamId": "17", "start": 31, "end": 55, "startKnown": true, "endKnown": false},
                            {"id": "2", "teamId": 3, "start": "x"}]}
        """)
        XCTAssertEqual(detail.footballDrives.first?.startKnown, true)
        XCTAssertEqual(detail.footballDrives.first?.endKnown, false)
        XCTAssertNil(detail.footballDrives.first?.knownEnd, "the feed says it couldn't place the end")
        XCTAssertEqual(detail.footballDrives.last?.teamId, "3")
        XCTAssertNil(detail.footballDrives.last?.start)
    }
}

/// Live football and baseball games for the situation tests: this server's NFL final turned
/// live (NE 3rd & 4 at the CHI 12, 0:41 left) and the Expo MLB final turned live (Top 7th, 3-2,
/// two outs, runners on 1st and 3rd). Detail stamped fresh unless `stale`.
enum SportsSituationFixtures {
    static let fresh = "2099-01-01T00:00:00Z"

    static func nflLive(_ overrides: [String: Any] = [:], detail: [String: Any] = [:], stale: Bool = false) -> SportsGamePage {
        var base = SportsGameFixtures.nflDetail
        base["updatedAt"] = stale ? "2026-01-01T00:00:00Z" : fresh
        base.merge(detail) { $1 }
        let live: [String: Any] = [
            "status": "live", "statusDetail": "0:41 - 4th Quarter", "period": "Q4", "clock": "0:41",
            "footballSituation": ["kind": "nfl", "possession": " NE ", "downDistance": "3rd & 4", "fieldPosition": "CHI 12",
                                  "awayTimeouts": 0, "homeTimeouts": 1],
        ]
        return SportsGameFixtures.page(live.merging(overrides) { $1 }, detail: base)
    }

    static func mlbJSON(_ overrides: [String: Any] = [:]) -> [String: Any] {
        let situation: [String: Any] = ["kind": "mlb", "inning": "Top 7th", "balls": 3, "strikes": 2, "outs": 2,
                                        "bases": "Runners on 1st & 3rd", "pitcher": "Jesus Luzardo", "batter": "Ozzie Albies"]
        var json: [String: Any] = [
            "id": "401816843", "league": "mlb", "sport": "baseball", "startTime": "2026-10-23T17:05:00Z",
            "status": "live", "statusDetail": "Top 7th", "period": "Top 7th", "clock": "0:00",
            "homeTeam": ["id": "22", "name": "Philadelphia Phillies", "abbreviation": "PHI", "color": "e81828", "score": "0"],
            "awayTeam": ["id": "15", "name": "Atlanta Braves", "abbreviation": "ATL", "color": "0c2340", "score": "0"],
            "liveSituation": situation,
            "detail": [
                "updatedAt": fresh, "stale": false, "capabilities": ["plays": true, "stats": true],
                "sport": situation.merging(["batterId": "33783", "pitcherId": 39667, "pitcherPitchCount": 94]) { $1 },
                "periods": (1...6).map { ["label": "\($0)", "away": "0", "home": "0"] } + [["label": "7", "away": "0", "home": ""]],
                "comparisons": [["label": "Hits", "away": "2", "home": "3"], ["label": "Errors", "away": "0", "home": "1"]],
                "playerStats": [
                    ["id": "33783", "teamId": "15", "name": "Ozzie Albies", "category": "Batting",
                     "stats": [["label": "AB", "value": "3"], ["label": "H", "value": "1"], ["label": "RBI", "value": "0"]]],
                    ["id": "39667", "teamId": "22", "name": "Jesus Luzardo", "category": "Pitching",
                     "stats": [["label": "IP", "value": "6.2"], ["label": "SO", "value": "9"]]],
                ],
            ] as [String: Any],
        ]
        json.merge(overrides) { $1 }
        return json
    }

    static func mlbLive(_ overrides: [String: Any] = [:]) -> SportsGamePage {
        SportsGamePage(game: SportsGameFixtures.decode(SportsGame.self, mlbJSON(overrides)), league: nil)
    }

    static func situation(_ overrides: [String: Any]) -> [String: Any] {
        ["kind": "mlb", "inning": "Top 7th", "balls": 3, "strikes": 2, "outs": 2, "bases": "Runners on 1st & 3rd"]
            .merging(overrides) { $1 }
    }
}
