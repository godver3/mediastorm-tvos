import XCTest
@testable import StrmrTV

/// Live TV's remembered HLS and join choices: kept per server and live source, and cleared by the reset.
@MainActor
final class LiveHLSPreferenceTests: XCTestCase {
    override func setUp() async throws {
        LiveHLSPreference.resetAll()
    }

    override func tearDown() async throws {
        LiveHLSPreference.resetAll()
    }

    func testRememberedPerServerAndSource() {
        let scope = LiveHLSPreference.Scope(server: "node:abc/1", sourceID: "xtream 1")
        XCTAssertFalse(LiveHLSPreference.prefersHLS(scope))
        LiveHLSPreference.remember(scope)
        XCTAssertTrue(LiveHLSPreference.prefersHLS(scope))
        XCTAssertFalse(LiveHLSPreference.prefersHLS(.init(server: "node:abc/1", sourceID: "xtream 2")))
        XCTAssertFalse(LiveHLSPreference.prefersHLS(.init(server: "node:other", sourceID: "xtream 1")))
    }

    func testStandardJoinRememberedOnSecondRunDry() {
        let scope = LiveHLSPreference.Scope(server: "node:abc/1", sourceID: "xtream 1")
        XCTAssertFalse(LiveHLSPreference.noteFastJoinRanDry(scope))
        XCTAssertFalse(LiveHLSPreference.prefersStandardJoin(scope))
        XCTAssertTrue(LiveHLSPreference.noteFastJoinRanDry(scope))
        XCTAssertTrue(LiveHLSPreference.prefersStandardJoin(scope))
        XCTAssertFalse(LiveHLSPreference.prefersHLS(scope))
        XCTAssertFalse(LiveHLSPreference.prefersStandardJoin(.init(server: "node:abc/1", sourceID: "xtream 2")))
        XCTAssertEqual(LiveHLSPreference.resetAll(), 1)
        XCTAssertFalse(LiveHLSPreference.prefersStandardJoin(scope))
    }

    func testResetForgetsEverySource() {
        LiveHLSPreference.remember(.init(server: "a", sourceID: "1"))
        LiveHLSPreference.remember(.init(server: "b", sourceID: "2"))
        XCTAssertEqual(LiveHLSPreference.resetAll(), 2)
        XCTAssertFalse(LiveHLSPreference.prefersHLS(.init(server: "a", sourceID: "1")))
        XCTAssertEqual(LiveHLSPreference.resetAll(), 0)
    }

    func testNoScopeWithoutALiveSource() async throws {
        let raw: [String: Any] = ["id": "c1", "name": "News", "url": "https://p.example/live/1.ts"]
        let channel = try JSONDecoder().decode(LiveChannel.self, from: JSONSerialization.data(withJSONObject: raw))
        let scope = await LiveHLSPreference.scope(for: channel)
        XCTAssertNil(scope)
    }
}
