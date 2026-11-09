import XCTest
@testable import StrmrTV

/// Which guide programmes a recording rule covers (the server's rule expansion), so the guide
/// offers to cancel or switch a series instead of re-creating it.
final class RecordingRuleMatchingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ raw: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func channel(_ id: String, tvg: String? = nil) throws -> LiveChannel {
        var raw: [String: Any] = ["id": id, "name": "Channel \(id)", "url": "https://example/\(id).m3u8"]
        if let tvg { raw["tvgId"] = tvg }
        return try decode(LiveChannel.self, raw)
    }

    private func rule(_ pattern: String, regex: Bool = false, channel: String? = nil) throws -> RecordingRule {
        var raw: [String: Any] = ["id": "r", "pattern": pattern, "matchType": regex ? "regex" : "title",
                                  "allChannels": channel == nil]
        if let channel { raw["channelId"] = channel }
        return try decode(RecordingRule.self, raw)
    }

    func testTitleRuleMatchesNormalizedTitleOnItsChannelOnly() throws {
        let r = try rule("The Simpsons", channel: "ch1")
        XCTAssertTrue(r.covers(title: "the simpsons", on: try channel("ch1")))
        XCTAssertTrue(r.covers(title: "The  Simpsons!", on: try channel("CH1")))
        XCTAssertFalse(r.covers(title: "The Simpsons", on: try channel("ch2")))
        XCTAssertFalse(r.covers(title: "The Simpsons Movie", on: try channel("ch1")))
        let byGuide = try decode(RecordingRule.self, ["id": "g", "pattern": "News", "tvgId": "cnn.us"])
        XCTAssertTrue(byGuide.covers(title: "News", on: try channel("other", tvg: "CNN.us")))
    }

    func testAllChannelsAndRegexRules() throws {
        let any = try rule("Jeopardy")
        XCTAssertTrue(any.covers(title: "JEOPARDY", on: try channel("ch9")))
        let regex = try rule("(news|weather)", regex: true)
        XCTAssertTrue(regex.covers(title: "Evening NEWS", on: try channel("ch3")))
        XCTAssertFalse(regex.covers(title: "Cartoons", on: try channel("ch3")))
        XCTAssertFalse(try rule("(", regex: true).covers(title: "(", on: try channel("ch3")))
    }

    func testNormalizedTitleMatchesServer() {
        XCTAssertEqual(RecordingRule.normalizedTitle("  Law & Order: SVU "), "law order svu")
        XCTAssertEqual(RecordingRule.normalizedTitle("Café 24/7"), "café 24 7")
    }
}
