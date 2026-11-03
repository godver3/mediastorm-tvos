import XCTest
@testable import StrmrTV

/// Stremio failover's choice of the next stream (Expo `nextUntriedStremioStreamIndex`).
final class StremioFailoverTests: XCTestCase {
    func testWalksUntriedStreamsInAddonOrder() {
        var failover = StremioFailover()
        failover.noteTuned(index: 2, available: [0, 2, 5])
        XCTAssertEqual(failover.next(), 0)
        XCTAssertEqual(failover.next(), 5)
        XCTAssertNil(failover.next())
    }

    func testServerPickCountsAsTheFirstStream() {
        // A direct stream reports no index: the server tuned the first playable one.
        var failover = StremioFailover()
        failover.noteTuned(index: nil, available: nil)
        XCTAssertNil(failover.next(), "nothing to try until the list is known")
        failover.learn(available: [1, 4])
        XCTAssertEqual(failover.next(), 4)
        XCTAssertNil(failover.next())
    }

    func testPickedStreamIsNotRetriedAfterLearningTheList() {
        var failover = StremioFailover()
        failover.noteTuned(index: 4, available: nil)
        failover.learn(available: [1, 4, 7])
        XCTAssertEqual(failover.next(), 1)
        XCTAssertEqual(failover.next(), 7)
        XCTAssertNil(failover.next())
    }

    func testLaterTunesKeepTheKnownList() {
        var failover = StremioFailover()
        failover.noteTuned(index: 0, available: [0, 1])
        failover.noteTuned(index: 1, available: nil)
        XCTAssertNil(failover.next())
    }

    func testDecodesSessionIndexes() throws {
        let json = #"{"sessionId":"a","playlistUrl":"/video/hls/a/stream.m3u8","stremioStreamIndex":3,"stremioStreamIndexes":[0,3,4]}"#
        let start = try JSONDecoder().decode(LiveStart.self, from: Data(json.utf8))
        XCTAssertEqual(start.stremioStreamIndex, 3)
        XCTAssertEqual(start.stremioStreamIndexes, [0, 3, 4])
    }
}
