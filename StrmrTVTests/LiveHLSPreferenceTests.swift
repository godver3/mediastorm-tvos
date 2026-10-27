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

    func testDirectPlayRulesOutTheFallback() {
        let scope = LiveHLSPreference.Scope(server: "node:abc/1", sourceID: "xtream 1")
        LiveHLSPreference.rememberDirectWorked(scope)
        LiveHLSPreference.remember(scope)
        XCTAssertTrue(LiveHLSPreference.directWorked(scope))
        XCTAssertFalse(LiveHLSPreference.prefersHLS(scope))
    }

    func testResetClearsOlderBuildsJoinChoice() {
        UserDefaults.standard.set("standard", forKey: "live.joinPreference.v1:a:1")
        XCTAssertEqual(LiveHLSPreference.resetAll(), 1)
        XCTAssertNil(UserDefaults.standard.string(forKey: "live.joinPreference.v1:a:1"))
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
