import XCTest
@testable import StrmrTV

/// The Sports hub's reading of `/api/sports` answers, after the Expo normaliser
/// (`features/sports/sports-backend-source.ts`) and follow ids (`sports-follows.ts`). The same
/// cases as the Android `SportsModelsTest`.
final class SportsModelTests: XCTestCase {
    private func game(_ overrides: [String: Any] = [:]) -> SportsGame {
        var json: [String: Any] = [
            "id": "401873010", "league": "nfl", "sport": "football", "title": "New England Patriots at Chicago Bears",
            "startTime": "2026-10-23T00:15:00Z", "endTime": "0001-01-01T00:00:00Z", "status": "final", "statusDetail": "Final",
            "homeTeam": ["id": "3", "name": "Chicago Bears", "abbreviation": "CHI", "color": "0b1c3a", "score": "30", "winner": true,
                         "logoUrl": "https://a.espncdn.com/i/teamlogos/nfl/500/scoreboard/chi.png"],
            "awayTeam": ["id": "17", "name": "New England Patriots", "abbreviation": "NE", "score": "24",
                         "logoUrl": "http://insecure.example/ne.png"],
        ]
        json.merge(overrides) { $1 }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(SportsGame.self, from: data)
    }

    func testDecodesAScoreboardGame() {
        let g = game()
        XCTAssertEqual(g.lifecycle, .final)
        XCTAssertTrue(g.isMatchup)
        XCTAssertTrue(g.showsScore)
        XCTAssertEqual(g.start, ISO8601DateFormatter().date(from: "2026-10-23T00:15:00Z"))
        XCTAssertNil(g.end, "Go's zero time is no end")
        XCTAssertNotNil(g.homeTeam.logo)
        XCTAssertNil(g.awayTeam.logo, "only https logos load")
    }

    func testLifecycleFromStatusText() {
        XCTAssertEqual(SportsLifecycle(status: "scheduled", detail: "Postponed"), .postponed)
        XCTAssertEqual(SportsLifecycle(status: "scheduled", detail: "Canceled"), .canceled)
        XCTAssertEqual(SportsLifecycle(status: "live", detail: "Rain Delay"), .delayed)
        XCTAssertEqual(SportsLifecycle(status: "live", detail: "Q3 4:12"), .live)
        XCTAssertEqual(SportsLifecycle(status: "pre", detail: "7:05 PM"), .scheduled)
    }

    func testNoScoreBeforeTheStart() {
        XCTAssertFalse(game(["status": "scheduled", "statusDetail": "7:05 PM"]).showsScore)
    }

    func testFightCardShowsItsName() {
        let card = game(["combat": ["cardName": "UFC 333: Volkanovski vs. Evloev"]])
        XCTAssertFalse(card.isMatchup)
        XCTAssertEqual(card.displayTitle, "UFC 333: Volkanovski vs. Evloev")
    }

    func testFollowIDsMatchExpo() {
        func league(_ id: String) -> SportsLeague {
            try! JSONDecoder().decode(SportsLeague.self, from: Data(#"{"id":"\#(id)","enabled":true}"#.utf8))
        }
        XCTAssertEqual(league("soccer-eng.1").followID, "premier-league")
        XCTAssertEqual(league("f1").followID, "formula-one")
        XCTAssertEqual(league("nhl").followID, "nhl")
    }

    func testUsableLeagues() {
        func league(_ json: String) -> SportsLeague { try! JSONDecoder().decode(SportsLeague.self, from: Data(json.utf8)) }
        XCTAssertTrue(league(#"{"id":"nba","enabled":true}"#).isUsable, "older servers send no status")
        XCTAssertTrue(league(#"{"id":"nba","enabled":true,"implementationStatus":"limited","capabilities":["schedule"]}"#).isUsable)
        XCTAssertFalse(league(#"{"id":"nba","enabled":true,"implementationStatus":"planned"}"#).isUsable)
        XCTAssertFalse(league(#"{"id":"nba","enabled":true,"capabilities":["standings"]}"#).isUsable)
        XCTAssertFalse(league(#"{"id":"nba","enabled":false}"#).isUsable)
    }
}
