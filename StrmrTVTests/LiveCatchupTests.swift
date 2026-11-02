import XCTest
@testable import StrmrTV

/// Provider catch-up: which channels and programmes replay, decoded from the server's channel JSON.
@MainActor
final class LiveCatchupTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_656_800) // 2026-11-02 22:00 UTC

    private func channel(catchup: [String: Any]?) throws -> LiveChannel {
        var raw: [String: Any] = ["id": "s:1", "name": "Animal Planet", "url": "http://h/1.ts", "sourceId": "s"]
        if let catchup { raw["catchup"] = catchup }
        return try JSONDecoder().decode(LiveChannel.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func program(start: TimeInterval, length: TimeInterval = 3600) throws -> EPGProgram {
        let f = ISO8601DateFormatter()
        let raw = ["title": "Show", "start": f.string(from: now.addingTimeInterval(start)),
                   "stop": f.string(from: now.addingTimeInterval(start + length))]
        return try JSONDecoder().decode(EPGProgram.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    func testDecodesCatchupAndReplaysPastProgrammesInTheWindow() throws {
        let archived = try channel(catchup: ["days": 2, "mode": "xc"])
        XCTAssertEqual(archived.catchup?.days, 2)
        XCTAssertTrue(archived.canReplay(try program(start: -3 * 3600), now: now))
        XCTAssertTrue(archived.canReplay(try program(start: -1800), now: now), "airing: Start Over")
        XCTAssertFalse(archived.canReplay(try program(start: 3600), now: now), "not aired yet")
        XCTAssertFalse(archived.canReplay(try program(start: -3 * 86_400), now: now), "past the archive")
    }

    func testChannelWithoutCatchupNeverReplays() throws {
        let plain = try channel(catchup: nil)
        XCTAssertNil(plain.catchupWindow)
        XCTAssertFalse(plain.canReplay(try program(start: -3 * 3600), now: now))
    }
}
