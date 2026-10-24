import XCTest
@testable import StrmrTV

/// Reading F1 timing archive channels, the cases of Expo's `sports-f1.test.ts` on a trimmed
/// excerpt of the recorded Monza capture (`replay/fixtures/f1-timing.json`).
final class SportsF1TimingTests: XCTestCase {
    private func archive(_ channels: String, session: String = "Race", mode: String = "archive") -> SportsF1Archive {
        SportsGameFixtures.decode(SportsF1Archive.self, """
            {"state":"available","mode":"\(mode)","eventId":"f1:600057442:401839102","sessionName":"\(session)",
             "checkedAt":"2026-09-12T16:31:00Z","capturedElapsed":"01:30:00","channels":\(channels)}
            """)
    }

    private lazy var race = archive("""
        {"DriverList":{
           "12":{"RacingNumber":"12","FullName":"Kimi ANTONELLI","Tla":"ANT","TeamName":"Mercedes"},
           "63":{"RacingNumber":"63","FullName":"George RUSSELL","Tla":"RUS","TeamName":"Mercedes"},
           "_kf":true,
           "99":{"FullName":"No Number"}},
         "TimingData":{"Lines":{
           "12":{"Position":"1","NumberOfLaps":53,"GapToLeader":"","IntervalToPositionAhead":{"Value":""},
                 "LastLapTime":{"Value":"1:24.010"},"BestLapTime":{"Value":"1:23.504"},"NumberOfPitStops":1,
                 "Sectors":[{"Value":"26.701"},{"Value":"27.120"},{"Value":"30.189"}]},
           "63":{"Position":"2","GapToLeader":"+3.857","IntervalToPositionAhead":{"Value":"+3.857"},"InPit":true,
                 "Sectors":{"0":{"Value":"26.900"},"2":{"Value":"30.400"}},"Retired":false}}},
         "TimingAppData":{"Lines":{
           "12":{"Stints":[{"Compound":"MEDIUM","TotalLaps":20,"StartLaps":0},{"Compound":"HARD","TotalLaps":36,"StartLaps":3}]},
           "63":{"Stints":{"0":{"Compound":"SOFT","TotalLaps":12,"StartLaps":3},"1":{"Compound":"HARD"}}}}},
         "RaceControlMessages":{"Messages":[
           {"Utc":"2026-09-06T13:03:00","Lap":1,"Category":"Flag","Flag":"GREEN","Message":"GREEN LIGHT - PIT EXIT OPEN"},
           {"Utc":"2026-09-06T13:40:12","Lap":21,"Category":"SafetyCar","Message":"SAFETY CAR DEPLOYED"},
           {"Utc":"2026-09-06T13:50:00","Lap":25,"Category":"Other","Message":""}]},
         "WeatherData":{"AirTemp":"27.4","TrackTemp":"44.1","Rainfall":"0"}}
        """)

    func testDriversInPositionOrderWithTheirTiming() {
        let drivers = SportsF1Timing.drivers(race)
        XCTAssertEqual(drivers.map(\.id), ["12", "63"], "entries without a racing number are left out")
        let leader = drivers[0]
        XCTAssertEqual(leader.name, "Kimi ANTONELLI")
        XCTAssertEqual(leader.abbreviation, "ANT")
        XCTAssertEqual(leader.position, 1)
        XCTAssertEqual(leader.laps, 53)
        XCTAssertEqual(leader.lastLap, "1:24.010")
        XCTAssertEqual(leader.bestLap, "1:23.504")
        XCTAssertEqual(leader.pitStops, 1)
        XCTAssertEqual(leader.sectors, ["26.701", "27.120", "30.189"])
        XCTAssertNil(leader.state)
        let second = drivers[1]
        XCTAssertEqual(second.interval, "+3.857")
        XCTAssertEqual(second.sectors, ["26.900", "", "30.400"], "sparse sector indexes keep their places")
        XCTAssertEqual(second.state, "In pit")
        XCTAssertNil(second.laps, "no laps reported is none, not zero")
    }

    func testStintsTakeOffAUsedSetsEarlierLaps() {
        let drivers = Dictionary(uniqueKeysWithValues: SportsF1Timing.drivers(race).map { ($0.id, $0) })
        XCTAssertEqual(drivers["12"]?.stints.map(\.laps), [20, 33])
        XCTAssertEqual(drivers["12"]?.stints.map(\.used), [false, true])
        let russell = drivers["63"]?.stints ?? []
        XCTAssertEqual(russell.map(\.compound), ["SOFT", "HARD"])
        XCTAssertEqual(russell.map(\.laps), [9, nil], "an unknown stint length stays unknown")
    }

    func testMessagesNewestFirstWithoutBlanks() {
        let messages = SportsF1Timing.messages(race)
        XCTAssertEqual(messages.map(\.message), ["SAFETY CAR DEPLOYED", "GREEN LIGHT - PIT EXIT OPEN"])
        XCTAssertEqual(messages[0].lap, 21)
        XCTAssertEqual(messages[1].flag, "GREEN")
    }

    func testWeatherLine() {
        XCTAssertEqual(SportsF1Timing.weather(race), "Air 27.4°C · Track 44.1°C · No rainfall reported")
    }

    func testQualifyingPartAndEntriesLeft() {
        let qualifying = archive("""
            {"DriverList":{"10":{"RacingNumber":"10","FullName":"Pierre GASLY","Tla":"GAS"}},
             "TimingData":{"SessionPart":2,"NoEntries":[20,15,10],"Lines":{"10":{"Position":"1","KnockedOut":true,
               "BestLapTimes":[{"Value":"1:22.612"},{"Value":"1:22.077"}]}}}}
            """, session: "Qualifying")
        XCTAssertEqual(SportsF1Timing.qualifying(qualifying), SportsF1Qualifying(part: 2, remaining: 15))
        let gasly = SportsF1Timing.drivers(qualifying).first
        XCTAssertEqual(gasly?.qualifyingTimes, ["1:22.612", "1:22.077", ""])
        XCTAssertEqual(gasly?.knockedOut, true)
        XCTAssertNil(SportsF1Timing.qualifying(race), "only qualifying archives have parts")
    }

    func testEmptyChannelsAreMissingValuesNotZeros() {
        let bare = archive(#"{"DriverList":{"1":{"RacingNumber":"1","FullName":"Driver"}}}"#, mode: "recorded")
        let driver = SportsF1Timing.drivers(bare).first
        XCTAssertNil(driver?.position)
        XCTAssertNil(driver?.laps)
        XCTAssertEqual(driver?.sectors, [])
        XCTAssertEqual(driver?.stints, [])
        XCTAssertTrue(SportsF1Timing.messages(bare).isEmpty)
        XCTAssertEqual(SportsF1Timing.weather(bare), "")
        XCTAssertTrue(bare.recorded)
        XCTAssertTrue(SportsF1Timing.drivers(SportsF1Archive()).isEmpty)
    }
}
