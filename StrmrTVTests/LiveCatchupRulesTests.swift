import XCTest
@testable import StrmrTV

/// Rewinding a live channel into the provider's catch-up: where a rewind lands, and what follows
/// an archive's end.
final class LiveCatchupRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_824_200) // 2026-11-04 20:30 UTC
    private let week: TimeInterval = 7 * 86_400
    private lazy var programs = [program("18:00", "19:00", "Earlier"), program("19:00", "20:00", "Before"),
                                 program("20:00", "22:00", "Game")]

    private func program(_ start: String, _ stop: String, _ title: String) -> EPGProgram {
        let raw = ["title": title, "start": "2026-11-04T\(start):00Z", "stop": "2026-11-04T\(stop):00Z"]
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(EPGProgram.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    func testProgramAtPicksTheOneAiring() {
        XCTAssertEqual(LiveCatchupRules.program(at: now, in: programs)?.title, "Game")
        XCTAssertEqual(LiveCatchupRules.program(at: now.addingTimeInterval(-45 * 60), in: programs)?.title, "Before")
        XCTAssertNil(LiveCatchupRules.program(at: now.addingTimeInterval(2 * 3600), in: programs))
    }

    func testRewindOpensTheProgrammeAtThatPoint() {
        let game = programs[2]
        XCTAssertEqual(LiveCatchupRules.seek(to: now.addingTimeInterval(-25 * 60), now: now, programs: programs, archiveWindow: week),
                       .archive(game, position: 5 * 60))
    }

    func testNearLiveOrOutsideTheArchive() {
        XCTAssertEqual(LiveCatchupRules.seek(to: now.addingTimeInterval(-30), now: now, programs: programs, archiveWindow: week), .live)
        XCTAssertEqual(LiveCatchupRules.seek(to: now.addingTimeInterval(-2 * 3600), now: now, programs: programs, archiveWindow: 3600),
                       .nothing)
        XCTAssertEqual(LiveCatchupRules.seek(to: now.addingTimeInterval(-5 * 3600), now: now, programs: programs, archiveWindow: week),
                       .nothing)
    }

    func testArchiveEndCarriesOnIntoTheNextProgramme() {
        let game = programs[2]
        let playhead = game.start.addingTimeInterval(120)
        XCTAssertEqual(LiveCatchupRules.continueAfter(playhead: playhead, played: 1200, now: now, programs: programs, archiveWindow: week),
                       .archive(game, position: 120))
    }

    func testArchiveEndAtLiveOrEmptyGoesLive() {
        XCTAssertEqual(LiveCatchupRules.continueAfter(playhead: now.addingTimeInterval(-20), played: 600, now: now,
                                                      programs: programs, archiveWindow: week), .live)
        XCTAssertEqual(LiveCatchupRules.continueAfter(playhead: now.addingTimeInterval(-600), played: 1, now: now,
                                                      programs: programs, archiveWindow: week), .live)
    }

    func testRewindFromAFreshTuneReachesAMinuteBack() {
        let now = Date(timeIntervalSince1970: 1_793_824_200)
        let near = now.addingTimeInterval(-10)
        XCTAssertEqual(LiveCatchupRules.rewindTarget(near, now: now), now.addingTimeInterval(-LiveCatchupRules.minimumBehind))
        let far = now.addingTimeInterval(-600)
        XCTAssertEqual(LiveCatchupRules.rewindTarget(far, now: now), far)
    }

    func testBarSeekInPlaceInArchiveOrLive() {
        let window = now.addingTimeInterval(-300)...now
        XCTAssertEqual(LiveCatchupRules.decide(now.addingTimeInterval(-5), now: now, loaded: window, programs: programs,
                                               archiveWindow: week), .live)
        let inWindow = now.addingTimeInterval(-120)
        XCTAssertEqual(LiveCatchupRules.decide(inWindow, now: now, loaded: window, programs: programs, archiveWindow: week),
                       .inPlayer(inWindow))
        XCTAssertEqual(LiveCatchupRules.decide(now.addingTimeInterval(-25 * 60), now: now, loaded: window, programs: programs,
                                               archiveWindow: week), .archive(programs[2], position: 5 * 60))
        // One press back from a fresh tune (nothing held): a minute back, into the archive.
        XCTAssertEqual(LiveCatchupRules.decide(now.addingTimeInterval(-10), now: now, loaded: nil, programs: programs,
                                               archiveWindow: week), .archive(programs[2], position: 29 * 60))
        // Forward past the archive's end, close to now: live.
        let archive = now.addingTimeInterval(-20 * 60)...now.addingTimeInterval(-10 * 60)
        XCTAssertEqual(LiveCatchupRules.decide(now.addingTimeInterval(-30), now: now, loaded: archive, programs: programs,
                                               archiveWindow: week), .live)
    }
}
