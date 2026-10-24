import XCTest
@testable import StrmrTV

/// The cycling calendar as the hub and the race page read it (Expo `sports-cycling.ts`, the hub's
/// cycling cards and `SportsCyclingDetailTV`), from trimmed excerpts of the Expo cycling samples.
final class SportsCyclingTests: XCTestCase {
    private let feed = SportsGameFixtures.decode(SportsCyclingFeed.self, """
    {"state":"available","source":{"provider":"Cycling organizers","observedAt":"2026-10-23T08:21:27Z"},"coverage":null,
     "data":[
      {"raceKind":"stage-race","id":"aso:tour:2026","name":"Tour de France","category":"men","startDate":"2026-10-01",
       "endDate":"2026-10-23","restDays":["2026-10-10","2026-10-17"],"source":{"provider":"ASO race center","observedAt":"2026-09-09T03:43:49Z"},
       "sourceUrl":"https://racecenter.letour.fr/en/","stages":[
         {"id":"aso:tour:2026:9","name":"Stage 9","date":"2026-10-09","status":"unknown",
          "results":{"state":"pending","source":{"provider":"ASO race center","observedAt":"2026-09-12T06:21:01Z"},"reason":"Select this stage to load published results."},
          "generalClassification":{"state":"pending","source":{"provider":"ASO race center","observedAt":"2026-09-12T06:21:01Z"}}},
         {"id":"aso:tour:2026:10","name":"Stage 10","date":"2026-10-11","status":"unknown",
          "results":{"state":"pending","source":{"provider":"ASO"}},"generalClassification":{"state":"pending","source":{"provider":"ASO"}}},
         {"id":"aso:tour:2026:21","name":"Stage 21","date":"2026-10-23","departure":"Thoiry","arrival":"Paris Champs-Élysées",
          "distance":"89 km","terrain":"Flat","status":"unknown","generalClassificationLabel":"After stage 21",
          "routeGuide":{"state":"available","source":{"provider":"ASO"},"sourceUrl":"https://www.letour.fr/en/stage-21",
                        "mapUrl":"https://img.aso.fr/map","profileUrl":"https://img.aso.fr/profile"},
          "results":{"state":"available","source":{"provider":"ASO race center","observedAt":"2026-09-09T15:52:13Z","updatedAt":"2026-08-17T09:45:48Z"},"data":[
            {"id":"r3","name":"Mads PEDERSEN","team":"LIDL-TREK","rank":3,"time":"1:58:49","gap":"+0:00"},
            {"id":"r1","name":"Mathieu VAN DER POEL","team":"ALPECIN-PREMIER TECH","rank":1,"time":"1:58:49","gap":"+0:00","bib":21,"nationality":"NED"},
            {"id":"r2","name":"Jasper PHILIPSEN","team":"ALPECIN-PREMIER TECH","rank":2,"time":"1:58:49"},
            {"id":"rx","name":"Out","team":"X","result":"DNF"},
            {"name":"No id"}]},
          "generalClassification":{"state":"available","source":{"provider":"ASO"},"data":[
            {"id":"g1","name":"Tadej POGACAR","rank":1,"time":"73:56:26","gap":"+0:00"},
            {"id":"g2","name":"Remco EVENEPOEL","rank":2,"time":"74:02:52","gap":"+6:26"}]}}]},
      {"raceKind":"one-day","id":"aso:paris-roubaix:2026","name":"Paris-Roubaix","category":"men","startDate":"2026-04-12",
       "endDate":"2026-04-12","captured":true,"source":{"provider":"ASO"},"stages":[{"id":"aso:paris-roubaix:2026:1","name":"Race","date":"2026-04-12"}]},
      {"id":"cro:cro-race:2026","name":"CRO Race","category":"men","scheduleOnly":true,"startDate":"2026-10-30","endDate":"2026-11-04",
       "source":{"provider":"CRO Race"},"stages":[{"id":"cro:cro-race:2026:1","name":"Stage 1","date":"2026-10-30","status":"scheduled"}]},
      {"name":"no id"}
     ]}
    """)
    private var tour: SportsCyclingRace { feed.races[0] }
    private let us = Locale(identifier: "en_US")

    func testDecodesTheFeedLeniently() throws {
        XCTAssertEqual(feed.races.count, 3, "a race without an id is skipped")
        XCTAssertTrue(feed.coverage.isEmpty)
        let stage = try XCTUnwrap(tour.stages.last)
        XCTAssertEqual(stage.route, "Thoiry → Paris Champs-Élysées")
        XCTAssertEqual(stage.results.rows.count, 4, "a result without an id is skipped")
        XCTAssertEqual(stage.results.rows.first { $0.id == "r1" }?.bib, 21)
        XCTAssertTrue(stage.completed)
        XCTAssertFalse(tour.stages[0].completed, "pending classifications have no rows")
        XCTAssertEqual(tour.followID, "aso:tour")
        XCTAssertEqual(feed.races[2].format, "stage-race")
        let path = try XCTUnwrap(SportsCycling.stagePath(stage.id))
        XCTAssertEqual([path.race, path.year, path.number], ["tour", "2026", "21"])
        XCTAssertNil(SportsCycling.stagePath("tour:21"))
    }

    func testHubListsTheDaysStageAndRestDays() throws {
        let today = SportsCycling.listings(feed.races, day: "2026-10-23")
        XCTAssertEqual(today.map(\.key), ["cycling:aso:tour:2026:21"])
        XCTAssertEqual(today.first?.lifecycle, .final, "results are in: a final card")

        let rest = try XCTUnwrap(SportsCycling.listings(feed.races, day: "2026-10-10").first)
        XCTAssertTrue(rest.restDay)
        XCTAssertNil(rest.stage)
        XCTAssertEqual(rest.lifecycle, .scheduled)
        XCTAssertEqual(rest.key, "cycling:aso:tour:2026")
        XCTAssertEqual(rest.nextStage?.name, "Stage 10")

        let noStage = SportsCycling.listings(feed.races, day: "2026-10-12")
        XCTAssertEqual(noStage.count, 1)
        XCTAssertFalse(noStage[0].restDay, "a day without a stage that isn't a rest day")
        XCTAssertTrue(SportsCycling.listings(feed.races, day: "2026-11-10").isEmpty, "outside a race's dates nothing shows")
        XCTAssertTrue(SportsCycling.listings(feed.races, day: "2026-10-23") { $0.id != "aso:tour:2026" }.isEmpty)
    }

    func testCardTexts() throws {
        let final = try XCTUnwrap(SportsCycling.listings(feed.races, day: "2026-10-23").first)
        XCTAssertEqual(SportsCyclingFormat.cardSubtitle(final), "Stage 21")
        XCTAssertEqual(SportsCyclingFormat.cardProgress(final), "89 km · Flat")
        XCTAssertEqual(SportsCyclingFormat.cardRows(final, spoilers: false), [
            SportsCyclingCardRow(rank: 1, name: "Mathieu VAN DER POEL", value: "+0:00"),
            SportsCyclingCardRow(rank: 2, name: "Jasper PHILIPSEN", value: "1:58:49"),
        ])
        XCTAssertTrue(SportsCyclingFormat.cardRows(final, spoilers: true).isEmpty, "Hide Scores empties the results")
        XCTAssertEqual(SportsCyclingFormat.cardEmpty(final, spoilers: true), "Hide Scores is on")
        XCTAssertEqual(SportsCyclingFormat.cardPill(final), "FINAL")

        let rest = try XCTUnwrap(SportsCycling.listings(feed.races, day: "2026-10-10").first)
        XCTAssertEqual(SportsCyclingFormat.cardPill(rest), "REST DAY")
        XCTAssertEqual(SportsCyclingFormat.cardSubtitle(rest), "Rest day")
        XCTAssertEqual(SportsCyclingFormat.cardProgress(rest), "Racing resumes \(SportsCycling.date("2026-10-11"))")
        XCTAssertEqual(SportsCyclingFormat.cardEmpty(rest, spoilers: false), "No racing scheduled today")

        let schedule = try XCTUnwrap(SportsCycling.listings(feed.races, day: "2026-10-30").first)
        XCTAssertEqual(SportsCyclingFormat.cardPill(schedule), "SCHEDULE")
        XCTAssertEqual(SportsCyclingFormat.cardLabel(schedule.race), "Cycling · Published schedule")
        XCTAssertEqual(SportsCyclingFormat.cardEmpty(schedule, spoilers: false), "Start time TBC · Find streams in event details")
    }

    func testDatesStagesAndTheCalendar() {
        XCTAssertEqual(SportsCycling.date("2026-10-23", locale: us), "Oct 23, 2026", "a date-only string stays on its day")
        XCTAssertEqual(SportsCycling.date(nil), "Date to be confirmed")
        XCTAssertEqual(SportsCycling.date("soon"), "Date to be confirmed")
        XCTAssertEqual(SportsCycling.date("2026-02-30"), "Date to be confirmed", "not a real day")
        XCTAssertEqual(SportsCycling.defaultStage(tour, today: "2026-10-12")?.name, "Stage 10")
        XCTAssertEqual(SportsCycling.defaultStage(tour, today: "2026-09-01")?.name, "Stage 9", "before the first stage: the first")
        XCTAssertEqual(SportsCycling.period(tour, today: "2026-10-23"), .current)
        XCTAssertEqual(SportsCycling.period(tour, today: "2026-10-24"), .past)
        XCTAssertEqual(SportsCycling.period(feed.races[2], today: "2026-10-23"), .upcoming)
        let ordered = feed.races.sorted { SportsCycling.calendarOrder($0, $1, today: "2026-10-23") }.map(\.name)
        XCTAssertEqual(ordered, ["Tour de France", "CRO Race", "Paris-Roubaix"])
        XCTAssertEqual(SportsCyclingFormat.stageOption(tour.stages[2]), "Stage 21 · \(SportsCycling.date("2026-10-23"))")
    }

    func testFindStreamsAndFollowing() {
        let stage = tour.stages[2]
        XCTAssertTrue(SportsCycling.canSearch(tour, stage, today: "2026-10-23"))
        XCTAssertFalse(SportsCycling.canSearch(tour, stage, today: "2026-10-24"), "a past stage")
        XCTAssertFalse(SportsCycling.canSearch(feed.races[1], feed.races[1].stages[0], today: "2026-04-01"), "a recorded capture")
        XCTAssertTrue(SportsCycling.isFollowed(tour, competitions: ["aso:tour"], pinned: []))
        XCTAssertTrue(SportsCycling.isFollowed(tour, competitions: [], pinned: ["cycling"]))
        XCTAssertEqual(SportsCycling.followRank(tour, competitions: ["nba"], pinned: ["basketball", "cycling"]), 2,
                       "after the one follow, second pin")
        XCTAssertEqual(SportsCycling.followRank(tour, competitions: [], pinned: []), Int.max)
    }

    func testPageTexts() {
        let stage = tour.stages[2]
        XCTAssertEqual(SportsCyclingFormat.stageState(tour, stage, stage.results), "Results")
        XCTAssertEqual(SportsCyclingFormat.overviewTab(tour), "Stage Overview")
        XCTAssertEqual(SportsCyclingFormat.overviewTab(feed.races[1]), "Race Overview")
        XCTAssertEqual(SportsCyclingFormat.resultsTitle(feed.races[1], overall: false, teams: false), "Race Classification")
        XCTAssertEqual(SportsCyclingFormat.resultsTitle(tour, overall: true, teams: false), "General Classification")
        XCTAssertEqual(SportsCyclingFormat.resultsTitle(tour, overall: false, teams: true), "Team Results")
        let pending = tour.stages[0]
        let notice = SportsCyclingFormat.emptyNotice(tour, pending, pending.results)
        XCTAssertEqual(notice.title, "Classification not available")
        XCTAssertEqual(notice.message, "The selected classification is not available in this feed.")
        let winner = stage.results.rows.first { $0.rank == 1 }!
        XCTAssertEqual(SportsCyclingFormat.riderLine(winner), "ALPECIN-PREMIER TECH · NED · Bib 21")
        XCTAssertEqual(SportsCyclingFormat.leaderValue(winner, gapFirst: false), "1:58:49", "the winner's time")
        XCTAssertEqual(SportsCyclingFormat.leaderValue(stage.generalClassification.rows[1], gapFirst: true), "+6:26")
    }
}
