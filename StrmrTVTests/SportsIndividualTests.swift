import XCTest
@testable import StrmrTV

/// The individual and other sports: golf's leaderboard, cricket's innings and scorecards, fight
/// cards and profiles (Go `SportsGolfEntry`, `SportsCricketInnings`, `SportsCricketScorecard`,
/// `SportsCombat`), and the rules ported from Expo `sports-tennis.ts`, `sports-combat-card.ts`,
/// `sports-rugby.ts`, `SportsSoccerPitch` and `SportsCricketOverview`.
final class SportsIndividualTests: XCTestCase {
    private typealias F = SportsGameFixtures

    private func game(_ league: String, sport: String, _ overrides: [String: Any] = [:], detail: [String: Any]? = nil) -> SportsGamePage {
        var json: [String: Any] = ["league": league, "sport": sport]
        json.merge(overrides) { $1 }
        return F.page(json, detail: detail)
    }

    // MARK: Decoding

    func testDecodesGolfCricketAndCombatDetail() {
        let page = game("pga", sport: "golf", detail: [
            "leaderboard": [
                ["id": "9478", "name": "Scottie Scheffler", "score": "-19", "rounds": [
                    ["round": 1, "strokes": "70", "toPar": "-2", "holes": [["hole": 1, "strokes": "4", "toPar": "E"], ["hole": "x"]]],
                    ["round": 2, "strokes": 68],
                ]],
                ["name": "no id: skipped"],
            ],
            "innings": [["teamId": "1298769", "number": 1, "runs": 155, "wickets": 8, "overs": 20, "description": "complete"],
                        ["teamId": "335970", "number": "bad"]],
            "cricketScorecards": [["kind": "bowling", "innings": 2, "teamName": "Gujarat Titans", "players": [
                ["id": "940973", "name": "Mohammed Siraj", "stats": [["label": "Wickets", "value": "1"]]]]], ["kind": "fielding", "innings": 1]],
            "fighterProfiles": [["id": "1", "teamId": "1", "name": "Jean Silva", "category": "Fighter profile",
                                 "stats": [["label": "Reach", "value": "70.5\""]]]],
        ])
        let detail = page.detail
        XCTAssertEqual(detail.leaderboard.map(\.name), ["Scottie Scheffler"])
        XCTAssertEqual(detail.leaderboard[0].rounds.map(\.strokes), ["70", "68"])
        XCTAssertEqual(detail.leaderboard[0].rounds[0].holes.count, 1)
        XCTAssertEqual(detail.leaderboard[0].latestRound, 2)
        XCTAssertEqual(detail.innings.count, 1)
        XCTAssertEqual(detail.innings[0].overs, "20")
        XCTAssertEqual(detail.cricketScorecards.map(\.kind), [.bowling])
        XCTAssertEqual(detail.cricketScorecards[0].players[0].value("Wickets"), "1")
        XCTAssertEqual(detail.fighterProfiles[0].value("Reach"), "70.5\"")
    }

    func testDecodesFightCardAndParticipants() {
        let game = F.game(["league": "ufc", "sport": "mma", "combat": [
            "cardName": "Noche UFC", "division": "Featherweight", "scheduledRounds": 5, "bouts": [
                ["id": "b1", "away": ["id": "1", "name": "Rodrigo Sezinando"], "home": ["id": "2", "name": "Daniil Donchenko", "winner": true],
                 "division": "Welterweight", "status": "final", "period": "Round 1", "clock": "4:27"],
                ["id": "b2", "away": ["id": "3"]],
            ]],
            "participants": [["id": 9478, "name": "Scottie Scheffler", "score": "-19"], ["id": "x"], "bad"]])
        XCTAssertEqual(game.combat?.scheduledRounds, 5)
        XCTAssertEqual(game.combat?.bouts.map(\.id), ["b1"])
        XCTAssertEqual(game.combat?.bouts[0].lifecycle, .final)
        XCTAssertEqual(game.participants?.items.map(\.id), ["9478"])
        XCTAssertEqual(game.participants?.items.first?.score, "-19")
    }

    // MARK: Tennis

    func testTennisContextTiebreaksAndLatestSet() {
        let titled = F.game(["league": "atp", "title": "US Open: Chak Lam Coleman Wong vs Chris Rodesch",
                             "awayTeam": ["id": "1", "name": "Chak Lam Coleman Wong"], "homeTeam": ["id": "2", "name": "Chris Rodesch"]])
        XCTAssertEqual(SportsTennis.eventContext(titled), "US Open")
        XCTAssertEqual(SportsTennis.eventContext(F.game(["league": "atp", "eventContext": " US Open · Men's Singles "])), "US Open · Men's Singles")
        XCTAssertNil(SportsTennis.eventContext(F.game()))
        XCTAssertEqual(SportsTennis.tiebreak(10), "¹⁰")
        XCTAssertEqual(SportsTennis.tiebreak(0), "⁰")
        XCTAssertEqual(SportsTennis.tiebreak(nil), "")
        let page = game("atp", sport: "tennis", detail: ["periods": [
            ["label": "Set 1", "away": "6", "home": "7", "awayTiebreak": 5, "homeTiebreak": 7, "homeWinner": true],
            ["label": "Set 2", "away": "3", "home": "2"], ["label": "Set 3", "away": "", "home": ""]]])
        let periods = page.detail.periods
        XCTAssertEqual(SportsTennis.latestSet(periods), 1)
        XCTAssertEqual(SportsTennis.games(periods[0], away: true), "6⁵")
        XCTAssertEqual(SportsTennis.games(periods[2], away: false), "–")
        XCTAssertTrue(SportsTennis.won(periods[0], away: false))
        let pair = F.decode(SportsTeam.self, ["id": "1", "name": "A Smith / B Jones", "seed": 3])
        XCTAssertEqual(SportsTennis.name(pair), "A Smith\nB Jones [3]")
    }

    // MARK: Combat

    func testCombatResultsPortraitsAndBars() {
        let final = F.game(["league": "ufc", "statusDetail": "Final", "period": "Round 2", "clock": "4:48",
                            "awayTeam": ["id": "5145766", "name": "Jean Silva"], "homeTeam": ["id": "4881999", "name": "Diego Lopes", "winner": true]])
        XCTAssertEqual(SportsCombatRules.result(final, hidden: false), "Diego Lopes wins · Round 2 · 4:48")
        XCTAssertEqual(SportsCombatRules.result(final, hidden: true), "Result hidden")
        let live = F.game(["league": "ufc", "status": "live", "statusDetail": "", "period": "Round 3", "clock": "–"])
        XCTAssertEqual(SportsCombatRules.result(live, hidden: false), "Round 3")
        XCTAssertEqual(SportsCombatRules.portrait(league: "ufc", fighter: final.homeTeam),
                       "https://a.espncdn.com/i/headshots/mma/players/full/4881999.png")
        XCTAssertNil(SportsCombatRules.portrait(league: "boxing", fighter: final.homeTeam))
        let logo = F.decode(SportsTeam.self, ["id": "1", "name": "X", "logoUrl": "https://a.espncdn.com/i/teamlogos/x.png"])
        XCTAssertNil(SportsCombatRules.portrait(league: "boxing", fighter: logo))
        XCTAssertEqual(SportsCombatRules.barValues(label: "Control time", away: "1:45", home: "2:38").map { [$0.0, $0.1] }, [105, 158])
        XCTAssertNil(SportsCombatRules.barValues(label: "Significant strike %", away: "45%", home: "52%"))
        XCTAssertNil(SportsCombatRules.barValues(label: "Knockdowns", away: "", home: "0"))
    }

    // MARK: Rugby

    func testRugbyStatusMarksAndOrder() {
        let live = game("rugby-180659", sport: "rugby", ["status": "live", "statusDetail": "64'", "period": "2nd", "clock": "64'"])
        XCTAssertEqual(SportsRugby.status(live), "Second half · 64'")
        XCTAssertEqual(SportsRugby.status(game("rugby-180659", sport: "rugby", ["status": "live", "statusDetail": "HT", "period": "1st"])),
                       "Half time")
        XCTAssertEqual(SportsRugby.status(game("rugby-180659", sport: "rugby")), "Full time")
        XCTAssertEqual(["try", "Penalty Try", "conversion", "penalty goal", "missed conversion", "yellow card", "substitute on"]
            .map(SportsRugby.mark), ["T", "PT", "C", "PG", "×", "YC", "↔"])
        let plays = [SportsPlay(id: "a", clock: "12'", title: "try"), SportsPlay(id: "b", clock: "40+2'", title: "try"),
                     SportsPlay(id: "c", clock: "33'", title: "penalty goal")]
        XCTAssertEqual(SportsRugby.latest(plays).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(SportsRugby.latest(plays + [SportsPlay(id: "d", title: "try")]).map(\.id), ["a", "b", "c", "d"])
    }

    // MARK: Soccer

    func testSoccerFormationsAndPossession() {
        XCTAssertEqual(SportsSoccerPitch.rows("4-2-3-1"), [1, 4, 2, 3, 1])
        XCTAssertNil(SportsSoccerPitch.rows("4-4-3"))
        XCTAssertNil(SportsSoccerPitch.rows("4-6"))
        XCTAssertNil(SportsSoccerPitch.rows(nil))
        XCTAssertEqual(SportsSoccerStats.possession("19%", "81").map { [$0.0, $0.1] }, [19, 81])
        XCTAssertNil(SportsSoccerStats.possession("40", "40"))
        XCTAssertEqual(SportsSoccerStats.display("0.83", label: "Pass accuracy %"), "83%")
        XCTAssertEqual(SportsSoccerStats.display("12", label: "Shots"), "12")
    }

    func testSoccerTimelineGoalsExcludeLatestAndRunOldestFirst() {
        let page = game("soccer-eng.1", sport: "soccer", ["status": "live"], detail: ["plays": [
            ["id": "4", "clock": "66'", "title": "Yellow Card"], ["id": "3", "clock": "61'", "title": "Goal - Header"],
            ["id": "2", "clock": "52'", "title": "Own Goal"], ["id": "1", "clock": "29'", "title": "Goal", "shootout": false],
            ["id": "0", "clock": "120'", "title": "Penalty - Scored", "shootout": true]]])
        XCTAssertEqual(SportsSoccerTimeline.latest(page)?.id, "4")
        XCTAssertEqual(SportsSoccerTimeline.goals(page).map(\.id), ["1", "2", "3"])
    }

    // MARK: Cricket

    func testCricketChaseAndLabels() {
        let page = game("cricket-8048", sport: "cricket", ["status": "live", "statusDetail": "RCB need 36 runs in 30 balls",
                                                           "awayTeam": ["id": "1298769", "name": "Gujarat Titans"],
                                                           "homeTeam": ["id": "335970", "name": "Royal Challengers Bengaluru"]],
                         detail: ["innings": [
                            ["teamId": "1298769", "number": 1, "runs": 155, "wickets": 8, "overs": "20"],
                            ["teamId": "335970", "number": 2, "runs": 120, "wickets": 3, "overs": "15", "target": 156, "batting": true]]])
        let lines = SportsCricket.lines(page)
        XCTAssertEqual(lines.map(\.innings.number), [2, 1])
        XCTAssertTrue(lines[0].current)
        XCTAssertEqual(lines[0].score, "120/3")
        XCTAssertEqual(lines[0].label, "1st innings")
        XCTAssertEqual(lines[0].chase, "Target 156 · 36 runs needed")
        XCTAssertEqual(lines[0].progress ?? 0, 120.0 / 156, accuracy: 0.001)
        XCTAssertEqual(lines[1].state, "1st innings")
        let missing = game("cricket-8048", sport: "cricket", detail: ["innings": [["teamId": "1", "number": 3, "runs": 10]]])
        XCTAssertEqual(SportsCricket.lines(missing)[0].label, "Match innings 3")
        XCTAssertEqual(SportsCricket.lines(missing)[0].score, "10/–")
    }

    func testCricketHighlightsOnlyLatestInningsOfAFinal() {
        let card = { (kind: String, innings: Int, players: [[String: Any]]) -> [String: Any] in
            ["kind": kind, "innings": innings, "teamName": "T", "players": players] }
        let detail: [String: Any] = ["cricketScorecards": [
            card("batting", 1, [["id": "a", "name": "Early", "stats": [["label": "Runs", "value": "90"]]]]),
            card("batting", 2, [["id": "b", "name": "Kohli", "stats": [["label": "Runs", "value": "75"]]],
                                ["id": "c", "name": "Iyer", "stats": [["label": "Runs", "value": "32"]]]]),
            card("bowling", 2, [["id": "d", "name": "Siraj", "stats": [["label": "Wickets", "value": "0"]]]])]]
        let final = SportsCricket.highlights(game("cricket-8048", sport: "cricket", detail: detail))
        XCTAssertEqual(final.innings, 2)
        XCTAssertEqual(final.players.map(\.player.name), ["Kohli"])
        XCTAssertEqual(final.players.first?.metric, "runs")
        XCTAssertTrue(SportsCricket.highlights(game("cricket-8048", sport: "cricket", ["status": "live"], detail: detail)).players.isEmpty)
    }

    // MARK: Hub card

    func testCardVariantsAndMonograms() {
        XCTAssertEqual(SportsCardVariant(game: F.game(["league": "atp"]), kind: .tennis), .tennis)
        XCTAssertEqual(SportsCardVariant(game: F.game(["league": "ufc", "combat": ["cardName": "UFC"]]), kind: .mma), .combat)
        let field = F.game(["league": "pga", "homeTeam": ["id": "", "name": ""], "awayTeam": ["id": "", "name": ""],
                            "participants": [["id": "1", "name": "Scottie Scheffler", "score": "-19"], ["id": "2", "name": "Ben Griffin"],
                                             ["id": "3", "name": "Third"]]])
        XCTAssertEqual(SportsCardVariant(game: field, kind: .golf), .field)
        XCTAssertEqual(SportsCardVariant(game: field, kind: .boxing), .field)
        XCTAssertEqual(SportsFieldCard.leaders(field).map(\.name), ["Scottie Scheffler", "Ben Griffin"])
        XCTAssertEqual(SportsCardVariant(game: F.game(), kind: .football), .matchup)
        let team = { (abbreviation: String, name: String) in F.decode(SportsTeam.self, ["id": "1", "name": name, "abbreviation": abbreviation]) }
        XCTAssertEqual(team("C. Rodesch", "Chris Rodesch").monogram, "CR")
        XCTAssertEqual(team("J.J. Spaun", "J.J. Spaun").monogram, "JS")
        XCTAssertEqual(team("RCB", "Royal Challengers Bengaluru").monogram, "RCB")
    }
}
