import XCTest
@testable import StrmrTV

/// On-device credits detection's decisions (the Expo detector's thresholds): when frames are
/// read, which lines count as credits, and when a run of samples marks the credits.
final class CreditsDetectionTests: XCTestCase {
    private let duration: Double = 1000
    private let card1 = ["Directed by", "Jane Smith", "Written by"]
    private let card2 = ["Director of Photography", "John Doe", "Edited by"]
    private let card3 = ["Music by", "Ann Lee", "Casting by"]

    /// Samples `lines` at `time`, as the player does: only when a sample is due.
    private func sample(_ d: inout CreditsDetection, _ lines: [String], at time: Double) -> Double? {
        XCTAssertTrue(d.shouldSample(at: time, duration: duration), "no sample due at \(time)")
        return d.record(lines, at: time)
    }

    func testNothingBeforeNinetyPercent() {
        var d = CreditsDetection()
        XCTAssertFalse(d.shouldSample(at: 899, duration: duration))
        XCTAssertTrue(d.shouldSample(at: 900, duration: duration))
    }

    func testCoarseThenFineInterval() {
        var d = CreditsDetection()
        XCTAssertNil(sample(&d, ["Previously"], at: 900))
        XCTAssertFalse(d.shouldSample(at: 904, duration: duration))
        XCTAssertNil(sample(&d, card1, at: 905))
        // Credit-like text seen: the next frame comes a second later.
        XCTAssertTrue(d.shouldSample(at: 906, duration: duration))
    }

    func testOneSampleInFlightAtATime() {
        var d = CreditsDetection()
        XCTAssertTrue(d.shouldSample(at: 900, duration: duration))
        XCTAssertFalse(d.shouldSample(at: 910, duration: duration))
        d.skip()
        XCTAssertTrue(d.shouldSample(at: 910, duration: duration))
    }

    func testRollingCreditsDetectedAtFirstSample() {
        var d = CreditsDetection()
        XCTAssertNil(sample(&d, card1, at: 950))
        XCTAssertNil(sample(&d, card2, at: 951))
        XCTAssertEqual(sample(&d, card3, at: 952), 950)
        XCTAssertEqual(d.detectedStart, 950)
        // Fires once.
        XCTAssertFalse(d.shouldSample(at: 960, duration: duration))
    }

    func testHeldCardIsNotCredits() {
        var d = CreditsDetection()
        XCTAssertNil(sample(&d, card1, at: 950))
        for t in 951...960 { XCTAssertNil(sample(&d, card1, at: Double(t))) }
        XCTAssertNil(d.detectedStart)
    }

    func testTextlessFrameBreaksTheRun() {
        var d = CreditsDetection()
        XCTAssertNil(sample(&d, card1, at: 950))
        XCTAssertNil(sample(&d, card2, at: 951))
        XCTAssertNil(sample(&d, [], at: 952))
        XCTAssertNil(sample(&d, card3, at: 957))
        XCTAssertNil(d.detectedStart)
    }

    func testSeekBackStartsOver() {
        var d = CreditsDetection()
        XCTAssertNil(sample(&d, card1, at: 950))
        XCTAssertNil(sample(&d, card2, at: 951))
        XCTAssertTrue(d.shouldSample(at: 920, duration: duration))
        XCTAssertFalse(d.isFine)
    }

    func testCreditLineFilter() {
        XCTAssertTrue(CreditsDetection.looksLikeCredit("director of photography"))
        XCTAssertTrue(CreditsDetection.looksLikeCredit("j r r tolkien"))
        XCTAssertFalse(CreditsDetection.looksLikeCredit("a"))
        XCTAssertFalse(CreditsDetection.looksLikeCredit("2024 1080 5 1"))
        XCTAssertFalse(CreditsDetection.looksLikeCredit(String(repeating: "word ", count: 13)))
        XCTAssertEqual(CreditsDetection.normalize("  Jane  O'Brien, Jr. "), "jane o brien jr")
        XCTAssertEqual(CreditsDetection.creditStrings(["Jane Smith", "JANE SMITH!", "12:00"]), ["jane smith"])
    }
}
