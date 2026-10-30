import XCTest
@testable import StrmrTV

/// Auto Switch's stall rules: stuck for a while, or short stalls again and again.
final class StallWatchTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Plays `seconds` of steady playback from `position`, one sample a second.
    private func play(_ watch: inout StallWatch, from position: Double, at time: Double, seconds: Int) -> Trigger? {
        var fired: StallWatch.Trigger?
        for s in 0...seconds {
            fired = fired ?? watch.sample(position: position + Double(s), active: true, now: start + time + Double(s))
        }
        return fired
    }

    /// Holds the playhead at `position` for `seconds`, one sample a second.
    private func stall(_ watch: inout StallWatch, at position: Double, time: Double, seconds: Int,
                       active: Bool = true) -> Trigger? {
        var fired: StallWatch.Trigger?
        for s in 1...seconds {
            fired = fired ?? watch.sample(position: position, active: active, now: start + time + Double(s))
        }
        return fired
    }

    typealias Trigger = StallWatch.Trigger

    func testStuckMidPlaybackFiresAfterTenSeconds() {
        var watch = StallWatch()
        XCTAssertNil(play(&watch, from: 100, at: 0, seconds: 30))
        XCTAssertNil(stall(&watch, at: 130, time: 30, seconds: 9))
        XCTAssertEqual(stall(&watch, at: 130, time: 39, seconds: 2), .stuck(seconds: 10))
    }

    func testSlowStartGetsTwentySeconds() {
        var watch = StallWatch()
        XCTAssertNil(stall(&watch, at: 0, time: 0, seconds: 19))
        XCTAssertEqual(stall(&watch, at: 0, time: 19, seconds: 2), .stuck(seconds: 20))
    }

    func testPausedNeverFires() {
        var watch = StallWatch()
        XCTAssertNil(play(&watch, from: 100, at: 0, seconds: 10))
        XCTAssertNil(stall(&watch, at: 110, time: 10, seconds: 120, active: false))
    }

    func testSeekLandingIsAllowedTheSlowStart() {
        var watch = StallWatch()
        XCTAssertNil(play(&watch, from: 100, at: 0, seconds: 10))
        // Seek to 1000 s, then a 15 s rebuffer there: under the 20 s settle limit.
        XCTAssertNil(stall(&watch, at: 1000, time: 10, seconds: 15))
        XCTAssertNil(play(&watch, from: 1000, at: 25, seconds: 5))
    }

    func testThreeShortStallsInTwoMinutesFire() {
        var watch = StallWatch()
        var time = 0.0
        XCTAssertNil(play(&watch, from: 100, at: time, seconds: 10))
        var position = 110.0
        time += 10
        var fired: Trigger?
        for _ in 0..<3 {
            fired = stall(&watch, at: position, time: time, seconds: 3)
            time += 3
            if fired != nil { break }
            XCTAssertNil(play(&watch, from: position, at: time, seconds: 20))
            position += 20
            time += 20
        }
        XCTAssertEqual(fired, .repeatedStalls(count: 3))
    }

    func testStallsSpreadOverMoreThanTwoMinutesDontFire() {
        var watch = StallWatch()
        var time = 0.0
        var position = 100.0
        XCTAssertNil(play(&watch, from: position, at: time, seconds: 5))
        position += 5
        time += 5
        for _ in 0..<4 {
            XCTAssertNil(stall(&watch, at: position, time: time, seconds: 3))
            time += 3
            XCTAssertNil(play(&watch, from: position, at: time, seconds: 70))
            position += 70
            time += 70
        }
    }
}
