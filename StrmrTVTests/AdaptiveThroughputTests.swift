import XCTest
@testable import StrmrTV

/// The Expo adaptive-throughput store (`services/adaptive-throughput.ts`) and speed-test maths
/// (`testBackendConnectionSpeedAggregate`, `refreshAdaptiveThroughputEstimate`).
final class AdaptiveThroughputTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: AdaptiveThroughputStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: "AdaptiveThroughputTests")!
        defaults.removePersistentDomain(forName: "AdaptiveThroughputTests")
        store = AdaptiveThroughputStore(defaults: defaults)
    }

    func testRouteKeyTrimsSlashesAndSpace() {
        XCTAssertEqual(AdaptiveThroughputStore.routeKey(" http://10.0.0.2:7777/// "), "http://10.0.0.2:7777")
        XCTAssertEqual(AdaptiveThroughputStore.routeKey("transport:iroh"), "transport:iroh")
    }

    func testSaveRoundsAndKeysByRoute() {
        let saved = store.save(route: "http://a:7777/", mbps: 84.26, source: .idle, measuredAt: now)
        XCTAssertEqual(saved, AdaptiveThroughputEstimate(measuredMbps: 84.3, measuredAt: 1_800_000_000, source: .idle))
        XCTAssertEqual(store.stored(for: "http://a:7777")?.measuredMbps, 84.3)
        XCTAssertNil(store.stored(for: "http://b:7777"), "another route has no estimate")
    }

    func testSaveRefusesNonPositiveSpeeds() {
        XCTAssertNil(store.save(route: "r", mbps: 0, source: .manual))
        XCTAssertNil(store.save(route: "r", mbps: .nan, source: .manual))
        XCTAssertNil(store.save(route: "r", mbps: .infinity, source: .manual))
        XCTAssertNil(store.stored(for: "r"))
    }

    func testFreshnessIsTwoHours() {
        store.save(route: "r", mbps: 50, source: .manual, measuredAt: now)
        XCTAssertNotNil(store.fresh(for: "r", now: now))
        XCTAssertNotNil(store.fresh(for: "r", now: now.addingTimeInterval(2 * 3600)), "exactly two hours")
        XCTAssertNil(store.fresh(for: "r", now: now.addingTimeInterval(2 * 3600 + 1)))
        XCTAssertNil(store.fresh(for: "r", now: now.addingTimeInterval(-1)), "measured in the future")
        XCTAssertNotNil(store.stored(for: "r"), "a stale estimate is still stored for Settings")
    }

    func testLatestSaveWinsAndPersists() {
        store.save(route: "r", mbps: 50, source: .idle, measuredAt: now)
        store.save(route: "r", mbps: 120, source: .manual, measuredAt: now)
        XCTAssertEqual(AdaptiveThroughputStore(defaults: defaults).stored(for: "r")?.source, .manual)
    }

    func testHeadersMatchExpoStrings() {
        XCTAssertEqual(AdaptiveThroughputEstimate(measuredMbps: 84.2, measuredAt: 1_800_000_000, source: .idle).headers,
                       ["X-Adaptive-Throughput-Mbps": "84.2", "X-Adaptive-Throughput-Measured-At": "1800000000"])
        XCTAssertEqual(AdaptiveThroughputEstimate.headerValue(120), "120")
    }

    func testFlowSplitSpreadsTheRemainder() {
        XCTAssertEqual(ConnectionSpeedTest.flowBytes(total: 10, streams: 4), [3, 3, 2, 2])
        XCTAssertEqual(ConnectionSpeedTest.flowBytes(total: 16 << 20, streams: 4), Array(repeating: 4 << 20, count: 4))
        XCTAssertEqual(ConnectionSpeedTest.flowBytes(total: 9, streams: 20).count, 8, "at most 8 flows")
    }

    func testAggregateSubtractsQuickestSetup() {
        let flows = [SpeedTestFlow(receivedBytes: 4_000_000, elapsedMs: 900, setupMs: 100, transferMs: 800),
                     SpeedTestFlow(receivedBytes: 4_000_000, elapsedMs: 1000, setupMs: 200, transferMs: 800)]
        let sample = ConnectionSpeedTest.aggregate(flows, elapsedMs: 1100)
        XCTAssertEqual(sample.setupMs, 100)
        XCTAssertEqual(sample.transferMs, 1000)
        XCTAssertEqual(sample.speedMbps, 64, accuracy: 0.0001, "8 MB in one second")
        XCTAssertEqual(sample.parallelStreams, 2)
    }

    func testLadderStopsOnceASampleIsLongEnough() {
        let short = ConnectionSpeedTest.aggregate([SpeedTestFlow(receivedBytes: 1, elapsedMs: 300, setupMs: 0, transferMs: 300)], elapsedMs: 300)
        let long = ConnectionSpeedTest.aggregate([SpeedTestFlow(receivedBytes: 1, elapsedMs: 800, setupMs: 0, transferMs: 800)], elapsedMs: 800)
        XCTAssertFalse(ConnectionSpeedTest.isLongEnough(short, plan: ConnectionSpeedTest.idle))
        XCTAssertTrue(ConnectionSpeedTest.isLongEnough(long, plan: ConnectionSpeedTest.idle))
        XCTAssertFalse(ConnectionSpeedTest.isLongEnough(long, plan: ConnectionSpeedTest.manual), "manual wants 1.5 s")
        XCTAssertEqual(ConnectionSpeedTest.idle.samples, [4 << 20, 16 << 20, 64 << 20])
    }
}
