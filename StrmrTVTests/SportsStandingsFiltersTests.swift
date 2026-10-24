import XCTest
@testable import StrmrTV

/// League standings (Expo `SportsLeagueStandings`, `participantWithStanding`) and the hub's Sport
/// and League filters (Expo `SportsHubTV`), from trimmed excerpts of real answers.
final class SportsStandingsFiltersTests: XCTestCase {
    private let nfl = SportsGameFixtures.decode(SportsLeagueStandings.self, """
    {"league":"nfl","state":"available","source":"ESPN","sourceUrl":"https://site.api.espn.com/x","updatedAt":"2026-10-23T14:21:27Z",
     "groups":[{"id":"8:0","title":"American Football Conference","season":2026,"seasonLabel":"2026",
       "columns":[{"key":"playoffSeed","label":"Seed"},{"key":"overall","label":"Record"},{"key":"wins","label":"Wins"},
                  {"key":"losses","label":"Losses"},{"key":"ties","label":"Draws"},{"key":"winPercent","label":"Win %"},
                  {"key":"gamesBehind","label":"GB"},{"key":"vs. Conf.","label":"Conference"},{"key":"streak","label":"Streak"}],
       "rows":[{"id":"12","name":"Kansas City Chiefs","abbreviation":"KC","kind":"team",
                "values":{"overall":"5-0","playoffSeed":"1","wins":"5","losses":"0","ties":"0","winPercent":"1.000","gamesBehind":"-"}},
               {"id":"7","name":"Denver Broncos","kind":"team","values":{"wins":"3","losses":"2","ties":"1","playoffSeed":"0"}},
               {"id":"9","name":"No Record","kind":"team","values":{"wins":"3","losses":"x"}},
               {"name":"no id"}]}]}
    """)
    private var table: SportsLeagueTable { nfl.groups[0] }

    private func team(_ id: String, record: String? = nil) -> SportsTeam {
        var json: [String: Any] = ["id": id, "name": "Team \(id)"]
        if let record { json["record"] = record }
        return SportsGameFixtures.decode(SportsTeam.self, json)
    }

    func testDecodesAndPicksColumns() {
        XCTAssertTrue(nfl.available)
        XCTAssertEqual(table.rows.count, 3, "a row without an id is skipped")
        XCTAssertEqual(SportsStandings.columns("nfl", table).map(\.label), ["Seed", "Record", "Win %", "GB"])
        XCTAssertEqual(SportsStandings.columns("college-football", table).map(\.key), ["overall", "vs. Conf.", "playoffSeed", "winPercent"])
        XCTAssertEqual(SportsStandings.value(table.rows[1], "playoffSeed"), "–", "a seed of 0 is none")
        XCTAssertEqual(SportsStandings.value(table.rows[1], "streak"), "–")
        XCTAssertEqual(SportsStandings.leader(table)?.name, "Kansas City Chiefs")
        XCTAssertEqual(SportsStandings.leaderEyebrow(table.rows[0]), "LEADING ENTRY · SEED 1")
        XCTAssertEqual(SportsStandings.leaderSummary(table.rows[0], table), "5-0 record")
        XCTAssertEqual(SportsStandings.groupLabel("mens-college-basketball"), "Conference")
        let unavailable = SportsGameFixtures.decode(SportsLeagueStandings.self, """
        {"league":"ufc","state":"unavailable","source":"ESPN","sourceUrl":"","reason":"Standings are not available for this competition"}
        """)
        XCTAssertTrue(unavailable.delayed)
        XCTAssertTrue(unavailable.groups.isEmpty)
    }

    func testRecordsForCardsThatLackThem() {
        let tables = nfl.groups
        XCTAssertEqual(SportsStandings.record(team("12"), tables), "5-0", "overall first")
        XCTAssertEqual(SportsStandings.record(team("espn:7"), tables), "3–2–1", "wins–losses–ties")
        XCTAssertNil(SportsStandings.record(team("9"), tables), "non-numeric losses")
        XCTAssertNil(SportsStandings.record(team("12", record: "4-1"), tables), "a record already sent wins")
        XCTAssertNil(SportsStandings.record(team("99"), tables), "no row")
        let game = SportsGameFixtures.game([
            "awayTeam": ["id": "12", "name": "KC"], "homeTeam": ["id": "7", "name": "DEN", "record": "2-2"],
        ])
        let filled = SportsStandings.withRecords(game, tables)
        XCTAssertEqual(filled.awayTeam.record, "5-0")
        XCTAssertEqual(filled.homeTeam.record, "2-2")
    }

    private let catalog = [
        #"{"id":"nfl","enabled":true,"name":"NFL","sport":"football","applicationSport":"american-football"}"#,
        #"{"id":"nba","enabled":true,"name":"NBA","sport":"basketball"}"#,
        #"{"id":"mens-college-basketball","enabled":true,"name":"NCAAM","sport":"basketball","college":true}"#,
        #"{"id":"nhl","enabled":true,"name":"NHL","sport":"hockey"}"#,
        #"{"id":"soccer-eng.1","enabled":false,"name":"Premier League","sport":"soccer"}"#,
        #"{"id":"f1","enabled":true,"name":"Formula 1","sport":"racing"}"#,
        #"{"id":"aso:tour","enabled":true,"name":"Tour de France","sport":"cycling","applicationSport":"cycling","implementationStatus":"limited","capabilities":["schedule"]}"#,
    ].map(SportsGameFixtures.league)

    func testSportChoicesFollowPins() {
        let ids = SportsHubFilters.sportOptions(catalog, pinned: ["cycling", "ice-hockey"]).map(\.id)
        XCTAssertEqual(ids, ["cycling", "ice-hockey", "american-football", "basketball", "motorsport", "college"])
        XCTAssertEqual(SportsHubFilters.sportLabel("ice-hockey"), "Hockey")
        XCTAssertEqual(SportsHubFilters.sportLabel("all"), "All Sports")
        XCTAssertEqual(SportsHubFilters.family(sport: "football"), "american-football")
    }

    func testLeagueChoicesFollowFollows() {
        let tour = SportsCyclingRace(id: "aso:tour:2026", name: "Tour de France")
        let all = SportsHubFilters.leagueOptions("all", catalog: catalog, cyclingRaces: [tour, SportsCyclingRace(id: "aso:tour:2025", name: "Tour de France")],
                                                 followed: ["nhl"], pinned: ["basketball"])
        XCTAssertEqual(all.map(\.id), ["nhl", "nba", "mens-college-basketball", "nfl", "f1", "aso:tour"])
        XCTAssertEqual(SportsHubFilters.leagueOptions("basketball", catalog: catalog, cyclingRaces: [], followed: [], pinned: []).map(\.id),
                       ["nba", "mens-college-basketball"])
        XCTAssertEqual(SportsHubFilters.leagueOptions("college", catalog: catalog, cyclingRaces: [], followed: [], pinned: []).map(\.id),
                       ["mens-college-basketball"])
        XCTAssertEqual(SportsHubFilters.leagueOptions("motorsport", catalog: catalog, cyclingRaces: [tour], followed: [], pinned: []).map(\.id),
                       ["f1"])
        XCTAssertEqual(SportsHubFilters.leagueOptions("cycling", catalog: catalog, cyclingRaces: [tour], followed: [], pinned: []).map(\.label),
                       ["Tour de France"])
    }

    func testFilterKeepsTheChosenSportAndLeague() {
        let nba = SportsFilterSubject(sport: "basketball", league: "nba")
        let college = SportsFilterSubject(sport: "basketball", league: "mens-college-basketball", college: true)
        XCTAssertTrue(SportsHubFilters.matches(nba, sport: "all", league: "all"))
        XCTAssertTrue(SportsHubFilters.matches(nba, sport: "basketball", league: "nba"))
        XCTAssertFalse(SportsHubFilters.matches(nba, sport: "basketball", league: "mens-college-basketball"))
        XCTAssertFalse(SportsHubFilters.matches(nba, sport: "college", league: "all"))
        XCTAssertTrue(SportsHubFilters.matches(college, sport: "college", league: "all"))
        XCTAssertFalse(SportsHubFilters.matches(SportsFilterSubject(sport: "motorsport", league: "f1"), sport: "cycling", league: "all"))
        let leagues = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        XCTAssertTrue(SportsHubFilters.hasDetails(sport: "all", league: "nba", catalog: leagues), "a team competition has standings")
        XCTAssertTrue(SportsHubFilters.hasDetails(sport: "motorsport", league: "all", catalog: leagues))
        XCTAssertTrue(SportsHubFilters.hasDetails(sport: "cycling", league: "all", catalog: leagues))
        XCTAssertFalse(SportsHubFilters.hasDetails(sport: "basketball", league: "all", catalog: leagues), "a sport alone")
        XCTAssertEqual(SportsHubFilters.rank(catalog[3], followed: ["nhl"], pinned: []), 0)
        XCTAssertEqual(SportsHubFilters.rank(catalog[1], followed: ["nhl"], pinned: ["basketball"]), 1)
    }
}
