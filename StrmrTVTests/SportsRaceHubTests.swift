import XCTest
@testable import StrmrTV

/// Which race sessions the Sports hub lists on a day and in what order, and how often it reloads
/// the race board: Expo `SportsHubTV`'s race items (one card per weekend in each lifecycle) and
/// `useSportsHubRaces` polling.
final class SportsRaceHubTests: XCTestCase {
    private let day = DateInterval(start: SportsGame.date("2026-10-23T06:00:00Z")!, end: SportsGame.date("2026-10-24T06:00:00Z")!)

    private func session(_ id: String, _ type: String, _ start: String, _ status: String, league: String = "motogp") -> SportsRaceEvent {
        SportsRaceEvent(id: "\(league):w:\(id)", providerEventId: "w", sessionId: id, sessionType: type, title: type, league: league,
                        eventKind: "race-session", startTime: start, status: status, participants: [
                            SportsRaceDriver(id: "c", name: "Third", position: 3), SportsRaceDriver(id: "u", name: "Unranked"),
                            SportsRaceDriver(id: "a", name: "First", position: 1), SportsRaceDriver(id: "b", name: "Second", position: 2),
                        ])
    }

    private func weekend(_ league: String, _ sessions: SportsRaceEvent...) -> SportsRaceEvent {
        SportsRaceEvent(id: "\(league):w", providerEventId: "w", title: "\(league) weekend", league: league, eventKind: "race",
                        startTime: sessions[0].startTime, status: "scheduled", subEvents: sessions)
    }

    private lazy var aragon = weekend(
        "motogp",
        session("fp1", "FP1", "2026-10-23T07:00:00Z", "final"),
        session("sprint", "Sprint", "2026-10-23T09:00:00Z", "final"),
        session("q2", "Q2", "2026-10-23T08:00:00Z", "final"),
        session("warmup", "Warm-up", "2026-10-23T15:00:00Z", "live"),
        session("race", "Race", "2026-10-23T18:00:00Z", "scheduled"),
        session("late", "Late", "2026-10-23T20:00:00Z", "scheduled"),
        session("tomorrow", "Tomorrow", "2026-10-24T07:00:00Z", "scheduled"))

    private func listings(_ board: SportsRaceBoard, include: (String) -> Bool = { _ in true }) -> [SportsRaceListing] {
        SportsRaceHub.listings(board, in: day, include: include)
    }

    func testOneCardPerWeekendInEachLifecycle() {
        let cards = listings(SportsRaceBoard(events: [aragon]))
        XCTAssertEqual(cards.count, 3)
        let byLifecycle = Dictionary(uniqueKeysWithValues: cards.map { ($0.lifecycle.key, $0.session.sessionType) })
        XCTAssertEqual(byLifecycle["final"], "Sprint", "the latest finished session")
        XCTAssertEqual(byLifecycle["live"], "Warm-up")
        XCTAssertEqual(byLifecycle["scheduled"], "Race", "the earliest session still to run")
        XCTAssertTrue(cards.allSatisfy { $0.weekend.id == aragon.id }, "the weekend comes along")
        XCTAssertEqual(Set(cards.map(\.key)).count, 3)
        XCTAssertEqual(Set(cards.map { SportsHubItem.race($0).id }).count, 3, "hub ids stay unique")
    }

    func testOnlyTheDaysSessionsOfEnabledSeries() {
        let f1 = weekend("f1", session("race", "Race", "2026-10-22T13:00:00Z", "final", league: "f1"))
        let board = SportsRaceBoard(events: [aragon, f1])
        XCTAssertTrue(listings(board).allSatisfy { $0.session.league != "f1" }, "yesterday's race isn't today's")
        XCTAssertTrue(listings(board) { $0 != "motogp" }.isEmpty)
        let tomorrow = SportsRaceHub.listings(board, in: DateInterval(start: day.end, duration: 86_400)) { _ in true }
        XCTAssertEqual(tomorrow.map(\.session.sessionType), ["Tomorrow"])
    }

    func testAWeekendWithoutSessionsStandsForItself() {
        let bare = SportsRaceEvent(id: "indycar:w", title: "Grand Prix", league: "indycar", startTime: "2026-10-23T19:00:00Z")
        let cards = listings(SportsRaceBoard(events: [bare]))
        XCTAssertEqual(cards.map(\.session.id), [bare.id])
        XCTAssertEqual(cards.first?.weekend.id, bare.id)
    }

    func testCardLeadersByPosition() {
        let cards = Dictionary(uniqueKeysWithValues: listings(SportsRaceBoard(events: [aragon])).map { ($0.lifecycle.key, $0) })
        XCTAssertEqual(cards["final"]?.leaders.map(\.id), ["a", "b", "c"], "three once final")
        XCTAssertEqual(cards["live"]?.leaders.map(\.id), ["a", "b"], "two while live")
    }

    func testBoardReloadCadence() {
        XCTAssertEqual(SportsRaceHub.refreshSeconds(SportsRaceBoard()), 30, "nothing came back")
        XCTAssertEqual(SportsRaceHub.refreshSeconds(SportsRaceBoard(events: [aragon])), 30, "a live session")
        let quiet = weekend("f1", session("race", "Race", "2026-10-23T13:00:00Z", "final", league: "f1"))
        XCTAssertEqual(SportsRaceHub.refreshSeconds(SportsRaceBoard(events: [quiet], leagues: [SportsRaceFeed(league: "f1")])), 60)
        XCTAssertEqual(SportsRaceHub.refreshSeconds(SportsRaceBoard(events: [quiet], leagues: [SportsRaceFeed(league: "f1", stale: true)])),
                       30, "a series is late")
        XCTAssertEqual(SportsRaceHub.refreshSeconds(SportsRaceBoard(events: [quiet],
                                                                    leagues: [SportsRaceFeed(league: "f1", unavailable: true)])), 30)
    }

    func testFollowedSeriesSortFirstWithExpoFollowIDs() {
        XCTAssertEqual(SportsRaceHub.followID("f1"), "formula-one")
        XCTAssertEqual(SportsRaceHub.followID("nascar"), "nascar-cup")
        XCTAssertEqual(SportsRaceHub.followID("indycar"), "indycar")
        XCTAssertEqual(SportsRaceHub.followID("motogp"), "motogp")
        let follows = ["nba", "motogp", "formula-one"]
        XCTAssertEqual(SportsRaceHub.followRank("f1", competitions: follows, pinned: []), 2)
        XCTAssertEqual(SportsRaceHub.followRank("motogp", competitions: follows, pinned: []), 1)
        XCTAssertEqual(SportsRaceHub.followRank("nascar", competitions: follows, pinned: []), Int.max)
        XCTAssertEqual(SportsRaceHub.followRank("nascar", competitions: follows, pinned: ["nfl", "motorsport"]), 4,
                       "a pinned motorsport comes after the follows")
        XCTAssertTrue(SportsRaceHub.isFollowed("nascar", competitions: [], pinned: ["motorsport"]))
        XCTAssertTrue(SportsRaceHub.isFollowed("indycar", competitions: ["indycar"], pinned: []))
        XCTAssertFalse(SportsRaceHub.isFollowed("f1", competitions: ["nba"], pinned: []))
        let ordered = ["nascar", "f1", "motogp"].sorted {
            SportsRaceHub.followRank($0, competitions: follows, pinned: []) < SportsRaceHub.followRank($1, competitions: follows, pinned: [])
        }
        XCTAssertEqual(ordered, ["motogp", "f1", "nascar"])
    }

    func testRacesShareTheHubOrderWithGames() {
        var ordering = SportsHubOrdering()
        let race = SportsHubItem.race(listings(SportsRaceBoard(events: [aragon])).first { $0.lifecycle == .live }!)
        let game = SportsHubItem.game(SportsGameFixtures.game(["id": "g", "status": "live", "startTime": "2026-10-23T14:00:00Z"]))
        ordering.record([race, game])
        XCTAssertEqual(ordering.ordered([race, game], in: .live, rank: { _ in 0 }).map(\.id), ["g", race.id], "by start, then kept")
        XCTAssertEqual(ordering.ordered([race, game], in: .live, rank: { $0 == race ? 0 : 1 }).first, race, "followed first")
        XCTAssertTrue(SportsSection.Kind.live.contains(race.lifecycle))
    }

    func testRacingSeriesOfTheCatalog() {
        XCTAssertTrue(SportsGameFixtures.league(#"{"id":"f1","enabled":true,"sport":"racing"}"#).isRacing)
        XCTAssertTrue(SportsGameFixtures.league(#"{"id":"espn:racing:nascar-truck","enabled":true}"#).isRacing)
        XCTAssertFalse(SportsGameFixtures.league(#"{"id":"nba","enabled":true,"sport":"basketball"}"#).isRacing)
    }
}
