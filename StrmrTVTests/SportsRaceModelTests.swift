import XCTest
@testable import StrmrTV

/// The race board, sessions and MotoGP answers as the race page reads them (Expo
/// `sports-racing.ts`, `SportsRaceTable`, `SportsRaceDetailTV`), from trimmed excerpts of the
/// recorded racing fixtures.
final class SportsRaceModelTests: XCTestCase {
    private let board = SportsGameFixtures.decode(SportsRaceBoard.self, """
        {"events":[
          {"id":"f1:600057442","providerEventId":"600057442","title":"Pirelli Italian Grand Prix","league":"f1","sport":"racing",
           "eventKind":"race","startTime":"2026-09-06T13:00:00Z","status":"final","statusDetail":"Final","participants":null,
           "updatedAt":"0001-01-01T00:00:00Z","unknownField":{"nested":true},
           "circuit":{"id":"it-1922","name":"Autodromo Nazionale Monza","location":"Monza","referenceLengthMeters":5793,
                      "coordinates":[[9.2811,45.6156],[9.2869,45.6189],[9.2905,45.6249],[9.2811,45.6156]],
                      "sourceUrl":"https://example.org/it-1922.geojson","attribution":"Circuit geometry"},
           "subEvents":[
             {"id":"f1:600057442:401839101","providerEventId":"600057442","sessionId":"401839101","sessionType":"Qual",
              "title":"Qual","league":"f1","eventKind":"race-session","startTime":"2026-09-05T14:00:00Z","status":"final",
              "updatedAt":"2026-09-09T03:06:52.960345786Z",
              "participants":[{"number":"10","team":"Alpine","result":"Classified","id":"5501","name":"Pierre Gasly","position":1,
                "statistics":[{"name":"lapsCompleted","label":"Laps","value":"18"},{"name":"qual3TimeMS","label":"Q3","value":"1:21.786"}]}]},
             {"id":"f1:600057442:401839102","providerEventId":"600057442","sessionId":"401839102","sessionType":"Race",
              "title":"Race","league":"f1","eventKind":"race-session","startTime":"2026-09-06T13:00:00Z","status":"final",
              "participants":[
                {"number":"12","team":"Mercedes","id":"5829","name":"Kimi Antonelli","position":1,"winner":true,
                 "statistics":[{"name":"lapsCompleted","label":"Laps","value":"53"},{"name":"totalTime","label":"Elapsed time","value":"1:51:15.281"}]},
                {"id":"bad","name":"Broken","position":"not a number"},
                {"number":"63","team":"Mercedes","id":"5503","name":"George Russell","position":2,
                 "statistics":[{"name":"behindTime","label":"Time behind","value":"+3.857"}]}]},
             {"id":"f1:600057442:401839098","providerEventId":"600057442","sessionId":"401839098","sessionType":"FP1",
              "title":"FP1","league":"f1","eventKind":"race-session","startTime":"2026-09-04T10:30:00Z","status":"final","participants":[]}
           ]},
          {"id":"nascar:202508313891:202508313891","providerEventId":"202508313891","sessionId":"202508313891","sessionType":"Race",
           "title":"Race","league":"nascar","eventKind":"race-session","startTime":"2025-08-31T22:00:00Z","status":"scheduled",
           "participants":[]}],
         "leagues":[{"league":"f1","stale":false,"unavailable":false},{"league":"motogp","stale":true,"unavailable":false}]}
        """)

    private var monza: SportsRaceEvent { board.events[0] }

    func testDecodesTheBoardLeniently() {
        XCTAssertEqual(board.events.count, 2)
        XCTAssertTrue(monza.participants.isEmpty, "a null participants list is empty")
        XCTAssertNil(monza.updated, "Go's zero time is no update")
        XCTAssertEqual(monza.subEvents.count, 3)
        XCTAssertNotNil(monza.subEvents[0].updated, "nanosecond fractions parse")
        XCTAssertEqual(monza.subEvents[1].participants.map(\.id), ["5829", "5503"], "an entry that fails to decode is skipped")
        XCTAssertTrue(board.delayed)
        XCTAssertEqual(monza.circuit?.referenceLengthMeters, 5793)
        XCTAssertEqual(monza.start, SportsGame.date("2026-09-06T13:00:00Z"))
    }

    func testResolvesWeekendsAndSessions() {
        XCTAssertEqual(board.resolve("f1:600057442")?.weekend.id, monza.id)
        XCTAssertNil(board.resolve("f1:600057442")?.session)
        XCTAssertEqual(board.resolve("f1:600057442:401839101")?.session, "f1:600057442:401839101")
        let lone = board.events[1]
        XCTAssertTrue(lone.isSession)
        XCTAssertEqual(board.resolve(lone.id)?.session, lone.id, "a lone session opens on itself")
        XCTAssertNil(board.resolve("motogp:missing"))
    }

    func testSessionsRunInStartOrderAndTheRaceIsTheDefault() {
        XCTAssertEqual(monza.sessions.map(\.sessionType), ["FP1", "Qual", "Race"])
        XCTAssertEqual(monza.defaultSession?.sessionType, "Race")
        var live = monza
        live.subEvents[0].status = "live"
        XCTAssertEqual(live.defaultSession?.sessionType, "Qual", "a live session wins")
        var practice = monza
        practice.subEvents.removeAll { $0.sessionType == "Race" }
        XCTAssertEqual(practice.defaultSession?.sessionType, "FP1", "no race: the last session listed, as Expo picks it")
        var bare = monza
        bare.subEvents = []
        XCTAssertTrue(bare.sessions.isEmpty, "a weekend listed without sessions has none to open")
        XCTAssertNil(bare.defaultSession)
    }

    func testTimingLabels() {
        func driver(_ stats: (String, String)...) -> SportsRaceDriver {
            SportsRaceDriver(id: "1", name: "A", statistics: stats.map { SportsRaceStatistic(name: $0.0, label: $0.0, value: $0.1) })
        }
        XCTAssertEqual(SportsRaceFormat.timing(driver(("behindTime", "+3.857"), ("totalTime", "1:51:19.138"))), "+3.857")
        XCTAssertEqual(SportsRaceFormat.timingKind(driver(("behindTime", "+3.857"))), "Gap")
        XCTAssertEqual(SportsRaceFormat.timing(driver(("behindLaps", "-2"))), "2 laps behind")
        XCTAssertEqual(SportsRaceFormat.timing(driver(("behindLaps", "1"))), "1 lap behind")
        XCTAssertEqual(SportsRaceFormat.timing(driver(("behindLaps", "0"), ("totalTime", "1:51:15.281"))), "1:51:15.281",
                       "zero laps behind is no gap")
        XCTAssertEqual(SportsRaceFormat.timingKind(driver(("totalTime", "1:51:15.281"))), "Time")
        XCTAssertEqual(SportsRaceFormat.timing(driver(("fastestLap", "01:45.455"))), "01:45.455")
        XCTAssertEqual(SportsRaceFormat.timingKind(driver(("fastestLap", "01:45.455"))), "Best lap")
        XCTAssertNil(SportsRaceFormat.timing(driver(("lapsCompleted", "53"))))
        XCTAssertEqual(SportsRaceFormat.cardValue(SportsRaceDriver(id: "2", name: "B", result: "DNF")), "DNF")
        XCTAssertNil(SportsRaceFormat.cardValue(SportsRaceDriver(id: "3", name: "C", result: "Classified")), "Classified goes unsaid")
    }

    func testCardTitlesAsExpo() {
        XCTAssertEqual(SportsRaceFormat.cardTitle("MICHELIN® GRAND PRIX OF ARAGON "), "Grand Prix of Aragon")
        XCTAssertEqual(SportsRaceFormat.cardTitle("Red Bull Grand Prix of The Americas"), "Grand Prix of the Americas")
        XCTAssertEqual(SportsRaceFormat.cardTitle("Pirelli Italian Grand Prix"), "Pirelli Italian Grand Prix")
        XCTAssertEqual(SportsRaceFormat.cardTitle("FORMULA 1 GRAN PREMIO DE MONACO"), "Formula 1 Gran Premio de Monaco")
        XCTAssertEqual(SportsRaceFormat.cardTitle("QATAR AIRWAYS AUSTRIAN GP"), "Qatar Airways Austrian GP")
    }

    func testSessionStates() {
        var race = monza.subEvents[1]
        XCTAssertEqual(SportsRaceFormat.sessionState(race), "Results")
        race.status = "live"
        XCTAssertEqual(SportsRaceFormat.sessionState(race), "Live")
        race.status = "scheduled"
        XCTAssertEqual(SportsRaceFormat.sessionState(race), "Scheduled")
        XCTAssertEqual(SportsRaceFormat.emptyNotice(race).title, "Race scheduled")
        race.statusDetail = "Postponed"
        XCTAssertEqual(SportsRaceFormat.sessionState(race), "Postponed")
        race.statusDetail = "Canceled"
        XCTAssertEqual(SportsRaceFormat.sessionState(race), "Cancelled")
        XCTAssertTrue(SportsRaceFormat.isQualifying(monza.subEvents[0]))
        XCTAssertEqual(SportsRaceFormat.watchTitle(monza, monza.subEvents[1]), "Pirelli Italian Grand Prix · Race")
    }

    func testWatchTarget() {
        var session = monza.subEvents[1]
        XCTAssertNil(SportsRaceHeader.watchTarget(monza, session), "nothing to watch once final")
        session.status = "live"
        let target = SportsRaceHeader.watchTarget(monza, session)
        XCTAssertEqual(target?.kind, "racing")
        XCTAssertEqual(target?.parentID, monza.id)
        XCTAssertEqual(target?.id, session.id)
        XCTAssertEqual(target?.live, true)
        session.stale = true
        XCTAssertNil(SportsRaceHeader.watchTarget(monza, session), "the server can't match a stale session")
    }

    func testCircuitOutlineFitsItsBox() throws {
        let outline = try XCTUnwrap(monza.circuit?.outline())
        XCTAssertEqual(outline.points.count, 4)
        XCTAssertTrue(outline.points.allSatisfy { (0...outline.width).contains($0.x) && (0...outline.height).contains($0.y) })
        XCTAssertEqual(outline.points[2].y, 0, accuracy: 1e-9, "north is up: the northernmost point has y 0")
        XCTAssertNil(SportsCircuit(coordinates: [[1, 1], [2, 2]]).outline(), "two points are no outline")
        XCTAssertNil(SportsCircuit(coordinates: [[1, 91], [2, 2], [3, 1]]).outline(), "latitude past the pole")
    }

    func testDecodesMotoGPStandingsAndCircuit() {
        let standings = SportsGameFixtures.decode(SportsMotoGPEnrichment.self, """
            {"state":"available","season":2026,"source":"MotoGP","sourceUrl":"https://www.motogp.com/en/world-standing",
             "standings":[{"riderId":"5cbd7eb6","name":"Jorge Martin","number":89,"team":"Aprilia Racing","constructor":"Aprilia",
                           "position":1,"points":256,"wins":1,"podiums":6},
                          {"riderId":"x","name":"Half Points","points":12.5}]}
            """)
        XCTAssertEqual(standings.season, 2026)
        XCTAssertEqual(standings.standings[0].manufacturer, "Aprilia")
        XCTAssertEqual(standings.standings[0].pointsText, "256")
        XCTAssertEqual(standings.standings[1].pointsText, "12.5", "half points keep their decimal")
        let guide = SportsGameFixtures.decode(SportsMotoGPEnrichment.self, """
            {"state":"stale","season":2026,"source":"MotoGP","sourceUrl":"","circuit":{"id":"1fe3","name":"MotorLand Aragón",
             "mapUrl":"https://photos.motogp.com/ara.png","lengthMeters":5077,"leftCorners":10,"rightCorners":7,"longestStraightMeters":968}}
            """)
        XCTAssertTrue(guide.stale)
        XCTAssertFalse(guide.unavailable)
        XCTAssertEqual(guide.circuit?.longestStraightMeters, 968)
        XCTAssertNotNil(guide.circuit?.map)
        XCTAssertEqual(SportsRaceFormat.kilometres(5077), "5.077 km")
    }
}
