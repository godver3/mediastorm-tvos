import XCTest
@testable import StrmrTV

/// The Play-by-Play tab's filters and pages (Expo `PlaysPanel`): newest first as sent, 16 to a
/// page; scoring plays, or goals for soccer and hockey by the event's title; soccer cards and
/// substitutions, hockey penalties and shots; one period at a time.
final class SportsPlayFeedTests: XCTestCase {
    private func plays(_ count: Int, period: (Int) -> String = { $0 < 20 ? "Q4" : "Q3" }) -> [SportsPlay] {
        (0..<count).map { SportsPlay(id: "\($0)", periodLabel: period($0), title: "Play \($0)", scoring: $0 % 5 == 0) }
    }

    func testPagesOfSixteenNewestFirst() {
        var feed = SportsPlayFeed(plays: plays(40), kind: .football)
        XCTAssertEqual(feed.pageCount, 3)
        XCTAssertEqual(feed.pagePlays.map(\.id).first, "0")
        XCTAssertEqual(feed.summary, "Newest first · 1–16 of 40")
        feed.page = 2
        XCTAssertEqual(feed.pagePlays.map(\.id), (32..<40).map(String.init))
        XCTAssertEqual(feed.summary, "Newest first · 33–40 of 40")
        feed.page = 9
        XCTAssertEqual(feed.currentPage, 2, "a page past the end shows the last")
    }

    func testOnePage() {
        XCTAssertEqual(SportsPlayFeed(plays: plays(5), kind: .basketball).summary, "Newest first · 5 plays")
        XCTAssertEqual(SportsPlayFeed(plays: plays(5), kind: .soccer).summary, "Newest first · 5 key events")
        XCTAssertEqual(SportsPlayFeed(plays: [], kind: .soccer).pageCount, 1)
    }

    func testScoringFilter() {
        let feed = SportsPlayFeed(plays: plays(40), kind: .football, filter: .scoring)
        XCTAssertEqual(feed.visible.map(\.id), ["0", "5", "10", "15", "20", "25", "30", "35"])
        XCTAssertEqual(feed.label(.scoring), "Scoring Plays")
        XCTAssertEqual(feed.emptyText, "No scoring plays in the loaded feed.")
        XCTAssertEqual(SportsPlayFeed(plays: [], kind: .football).emptyText, "No plays in the loaded feed.")
    }

    func testSoccerGoalsAndCardsComeFromTheTitle() {
        let events = [
            SportsPlay(id: "1", periodLabel: "H2", title: "Penalty - Scored"),
            SportsPlay(id: "2", periodLabel: "H2", title: "Yellow Card"),
            SportsPlay(id: "3", periodLabel: "H1", title: "Substitution"),
            SportsPlay(id: "4", periodLabel: "H1", title: "Red Card"),
            SportsPlay(id: "5", periodLabel: "H1", title: "Goal - Header", description: "Goal!", scoring: false),
        ]
        let feed = SportsPlayFeed(plays: events, kind: .soccer)
        XCTAssertEqual(feed.filters, [.all, .scoring, .cards, .substitutions])
        XCTAssertEqual(feed.label(.all), "All Key Events")
        XCTAssertEqual(feed.label(.scoring), "Goals")
        XCTAssertEqual(SportsPlayFeed(plays: events, kind: .soccer, filter: .scoring).visible.map(\.id), ["1", "5"])
        XCTAssertEqual(SportsPlayFeed(plays: events, kind: .soccer, filter: .cards).visible.map(\.id), ["2", "4"])
        XCTAssertEqual(SportsPlayFeed(plays: events, kind: .soccer, filter: .substitutions).visible.map(\.id), ["3"])
    }

    func testHockeyPenaltiesAndShots() {
        let events = [
            SportsPlay(id: "1", title: "Shot on Goal"), SportsPlay(id: "2", title: "Minor Penalty"),
            SportsPlay(id: "3", title: "Goal", scoring: true), SportsPlay(id: "4", title: "Faceoff"),
            SportsPlay(id: "5", title: "Blocked Shot"),
        ]
        XCTAssertEqual(SportsPlayFeed(plays: events, kind: .hockey).filters, [.all, .scoring, .penalties, .shots])
        XCTAssertEqual(SportsPlayFeed(plays: events, kind: .hockey, filter: .penalties).visible.map(\.id), ["2"])
        XCTAssertEqual(SportsPlayFeed(plays: events, kind: .hockey, filter: .shots).visible.map(\.id), ["1", "3", "5"])
        XCTAssertEqual(SportsPlayFeed(plays: events, kind: .basketball).filters, [.all, .scoring])
    }

    func testPeriods() {
        var feed = SportsPlayFeed(plays: plays(30) + [SportsPlay(id: "x", title: "No period")], kind: .football)
        XCTAssertEqual(feed.periods, ["Q4", "Q3"], "in feed order, empty labels left out")
        feed.period = "Q3"
        XCTAssertEqual(feed.visible.count, 10)
        XCTAssertEqual(feed.pageCount, 1)
        feed.period = "Q1"
        XCTAssertNil(feed.activePeriod, "a period the feed no longer has shows them all")
        XCTAssertEqual(feed.visible.count, 31)
    }

    func testEventKinds() {
        XCTAssertEqual(SportsEventKind(title: "Own Goal"), .goal)
        XCTAssertEqual(SportsEventKind(title: "power_play goal"), .goal)
        XCTAssertEqual(SportsEventKind(title: "Second Yellow Card"), .redCard)
        XCTAssertEqual(SportsEventKind(title: "Penalty Saved"), .penalty)
        XCTAssertEqual(SportsEventKind(title: "Shot"), .other)
    }
}
