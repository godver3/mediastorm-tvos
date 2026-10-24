import XCTest
@testable import StrmrTV

/// The multiscreen slot state machine (the Expo app's `TVMultiscreenSession`) over a fake transport.
@MainActor
final class MultiscreenSessionTests: XCTestCase {
    private final class FakeTransport: MultiscreenTransport {
        var log: [String] = []
        var failStart = Set<String>()
        var noURL = Set<String>()
        var failStop = Set<String>()
        /// Channels whose start waits until `release(_:)`.
        var held = Set<String>()
        private var waiting: [String: CheckedContinuation<Void, Never>] = [:]
        private var count = 0

        func start(_ channel: LiveChannel) async throws -> (sessionID: String?, url: URL?) {
            log.append("start \(channel.id)")
            if held.contains(channel.id) {
                await withCheckedContinuation { waiting[channel.id] = $0 }
            }
            if failStart.contains(channel.id) { throw URLError(.badServerResponse) }
            count += 1
            let id = "\(channel.id)-\(count)"
            return (id, noURL.contains(channel.id) ? nil : URL(string: "http://server/\(id).m3u8"))
        }

        func stop(_ sessionID: String) async throws {
            if failStop.contains(sessionID) { throw URLError(.timedOut) }
            log.append("stop \(sessionID)")
        }

        func release(_ channel: String) {
            held.remove(channel)
            waiting.removeValue(forKey: channel)?.resume()
        }

        func until(_ entry: String) async {
            for _ in 0..<200 where !log.contains(entry) { await Task.yield() }
        }
    }

    private static func channel(_ id: String, source: String? = "a") -> LiveChannel {
        LiveChannel(id: id, name: id.uppercased(), url: "http://provider/\(id)", logo: nil, group: nil, tvgId: nil,
                    tvgName: nil, sourceId: source, sourceName: nil, playbackId: nil)
    }

    private var transport: FakeTransport!
    private var session: MultiscreenSession!

    override func setUp() async throws {
        transport = FakeTransport()
        session = MultiscreenSession(transport: transport)
    }

    func testStartsWithTwoEmptySlots() {
        XCTAssertEqual(session.slots.count, 2)
        XCTAssertEqual(session.occupied, [])
    }

    func testTunePlaysTheSession() async {
        let task = session.tune(0, to: Self.channel("bbc"))
        XCTAssertTrue(session.slots[0].loading, "shows tuning at once")
        await task.value
        let slot = session.slots[0]
        XCTAssertEqual(slot.channel?.id, "bbc")
        XCTAssertEqual(slot.sessionID, "bbc-1")
        XCTAssertEqual(slot.source?.url.absoluteString, "http://server/bbc-1.m3u8")
        XCTAssertFalse(slot.loading)
        XCTAssertNil(slot.error)
        XCTAssertTrue(slot.isPlaying)
    }

    func testDuplicateChannelFocusesItsSlot() async {
        await session.tune(0, to: Self.channel("bbc")).value
        session.focus(1)
        await session.tune(1, to: Self.channel("bbc")).value
        XCTAssertEqual(session.focusedIndex, 0)
        XCTAssertNil(session.slots[1].channel)
        XCTAssertEqual(transport.log, ["start bbc"])
    }

    func testSameIDFromAnotherSourceIsNotADuplicate() async {
        await session.tune(0, to: Self.channel("bbc", source: "a")).value
        await session.tune(1, to: Self.channel("bbc", source: "b")).value
        XCTAssertEqual(session.slots[1].channel?.sourceId, "b")
    }

    func testDuplicateOfAnInFlightTuneFocusesIt() async {
        transport.held = ["bbc"]
        let first = session.tune(0, to: Self.channel("bbc"))
        session.focus(1)
        await session.tune(1, to: Self.channel("bbc")).value
        XCTAssertEqual(session.focusedIndex, 0)
        transport.release("bbc")
        await first.value
        XCTAssertEqual(transport.log, ["start bbc"])
    }

    func testRetuneReleasesTheOldSessionFirst() async {
        await session.tune(0, to: Self.channel("bbc")).value
        await session.tune(0, to: Self.channel("itv")).value
        XCTAssertEqual(transport.log, ["start bbc", "stop bbc-1", "start itv"])
        XCTAssertEqual(session.slots[0].channel?.id, "itv")
    }

    func testFailedStartKeepsTheChannelWithAnError() async {
        transport.failStart = ["bbc"]
        await session.tune(0, to: Self.channel("bbc")).value
        XCTAssertEqual(session.slots[0].channel?.id, "bbc")
        XCTAssertEqual(session.slots[0].error, MultiscreenSession.tuneError)
        XCTAssertFalse(session.slots[0].loading)
        XCTAssertNil(session.slots[0].source)
    }

    func testSessionWithoutAStreamIsStopped() async {
        transport.noURL = ["bbc"]
        await session.tune(0, to: Self.channel("bbc")).value
        XCTAssertEqual(transport.log, ["start bbc", "stop bbc-1"])
        XCTAssertEqual(session.slots[0].error, MultiscreenSession.tuneError)
        XCTAssertNil(session.slots[0].sessionID)
    }

    func testFailedCleanupKeepsTheSessionForExit() async throws {
        transport.noURL = ["bbc"]
        transport.failStop = ["bbc-1"]
        await session.tune(0, to: Self.channel("bbc")).value
        XCTAssertEqual(session.slots[0].sessionID, "bbc-1", "kept so exit can retry the stop")
        transport.failStop = []
        try await session.close()
        XCTAssertTrue(transport.log.contains("stop bbc-1"))
    }

    func testStaleTuneGivesWayToTheNewerOne() async {
        transport.held = ["bbc"]
        let stale = session.tune(0, to: Self.channel("bbc"))
        await transport.until("start bbc")
        let newer = session.tune(0, to: Self.channel("itv"))
        transport.release("bbc")
        await stale.value
        await newer.value
        XCTAssertEqual(session.slots[0].channel?.id, "itv")
        XCTAssertTrue(transport.log.contains("stop bbc-1"), "the stale session is released")
        XCTAssertEqual(transport.log.last, "start itv")
    }

    func testFailIgnoresAnOldSource() async {
        await session.tune(0, to: Self.channel("bbc")).value
        let old = session.slots[0].source!
        await session.tune(0, to: Self.channel("itv")).value
        session.fail(0, source: old)
        XCTAssertNil(session.slots[0].error)
        session.fail(0, source: session.slots[0].source!)
        XCTAssertEqual(session.slots[0].error, MultiscreenSession.streamError)
        XCTAssertFalse(session.slots[0].isPlaying)
    }

    func testListenNeedsASource() async {
        session.listen(1)
        XCTAssertEqual(session.audioIndex, 0)
        await session.tune(1, to: Self.channel("bbc")).value
        session.listen(1)
        XCTAssertEqual(session.audioIndex, 1)
    }

    func testRemovingTheAudibleSlotMovesAudio() async {
        await session.tune(0, to: Self.channel("bbc")).value
        await session.tune(1, to: Self.channel("itv")).value
        session.listen(0)
        await session.remove(0).value
        XCTAssertNil(session.slots[0].channel)
        XCTAssertEqual(session.audioIndex, 1)
        XCTAssertTrue(transport.log.contains("stop bbc-1"))
    }

    func testFailedRemoveReportsIt() async {
        await session.tune(0, to: Self.channel("bbc")).value
        transport.failStop = ["bbc-1"]
        await session.remove(0).value
        XCTAssertEqual(session.slots[0].error, MultiscreenSession.releaseError)
        XCTAssertEqual(session.slots[0].sessionID, "bbc-1")
    }

    func testAddsSlotsUpToFour() async {
        for (i, id) in ["a", "b", "c", "d", "e"].enumerated() {
            await session.tune(i, to: Self.channel(id)).value
        }
        XCTAssertEqual(session.slots.count, MultiscreenSession.maxScreens)
        XCTAssertFalse(transport.log.contains("start e"))
        await session.tune(7, to: Self.channel("f")).value
        XCTAssertEqual(session.slots.count, 4, "only the next index adds a slot")
    }

    func testCloseStopsEverySessionAndRetriesFailures() async throws {
        await session.tune(0, to: Self.channel("bbc")).value
        await session.tune(1, to: Self.channel("itv")).value
        transport.failStop = ["itv-2"]
        do {
            try await session.close()
            XCTFail("a failed stop must throw")
        } catch {}
        XCTAssertNil(session.slots[0].sessionID)
        XCTAssertEqual(session.slots[1].sessionID, "itv-2")
        transport.failStop = []
        try await session.close()
        XCTAssertTrue(transport.log.contains("stop itv-2"))
        await session.tune(0, to: Self.channel("c4")).value
        XCTAssertFalse(transport.log.contains("start c4"), "closed: no more tunes")
    }

    func testCloseCancelsATuneStillQueued() async throws {
        transport.held = ["bbc"]
        let tune = session.tune(0, to: Self.channel("bbc"))
        await transport.until("start bbc")
        let close = Task { try await session.close() }
        transport.release("bbc")
        await tune.value
        try await close.value
        XCTAssertTrue(transport.log.contains("stop bbc-1"))
        XCTAssertNil(session.slots[0].source)
    }

    func testAdoptedSessionIsOwned() async throws {
        let url = URL(string: "http://server/handed.m3u8")!
        session.adopt(Self.channel("bbc"), url: url, sessionID: "handed")
        XCTAssertTrue(session.slots[0].isPlaying)
        XCTAssertEqual(session.index(of: Self.channel("bbc")), 0)
        try await session.close()
        XCTAssertEqual(transport.log, ["stop handed"])
    }
}
