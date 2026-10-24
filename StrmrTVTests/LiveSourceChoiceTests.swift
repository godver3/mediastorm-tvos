import XCTest
@testable import StrmrTV

/// Choose Source on a Stremio channel: which channels offer it, the streams list, and the
/// picked stream carried into the tune query.
@MainActor
final class LiveSourceChoiceTests: XCTestCase {
    private func channel(_ url: String) throws -> LiveChannel {
        let raw: [String: Any] = ["id": "s:1", "name": "Sky Sports", "url": url, "sourceId": "s"]
        return try JSONDecoder().decode(LiveChannel.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    func testOnlyStremioStreamResourcesOfferSources() throws {
        XCTAssertTrue(try channel("https://addon.example/stream/tv/sky.json").hasStremioSources)
        XCTAssertTrue(try channel("https://addon.example/cfg/stream/tv/sky.json?x=1").hasStremioSources)
        XCTAssertFalse(try channel("https://provider.example/live/u/p/123.ts").hasStremioSources)
        XCTAssertFalse(try channel("https://addon.example/catalog/tv/all.json").hasStremioSources)
        XCTAssertFalse(try channel("stremio://addon.example/stream/tv/sky.json").hasStremioSources)
    }

    func testDecodesStreamsAndPicksIndex() throws {
        let json = #"{"streams":[{"index":0,"label":"HD · English"},{"index":3,"label":"FHD","name":"Addon"}]}"#
        struct Response: Decodable { let streams: [LiveStremioStream] }
        let streams = try JSONDecoder().decode(Response.self, from: Data(json.utf8)).streams
        XCTAssertEqual(streams.map(\.index), [0, 3])

        let base = try channel("https://addon.example/stream/tv/sky.json")
        XCTAssertNil(base.stremioStreamIndex)
        let picked = LiveSourceChoice(channel: base, streams: streams).channel(streamIndex: 3)
        XCTAssertEqual(picked.stremioStreamIndex, 3)
        XCTAssertEqual(picked.id, base.id)
    }

    func testTuneQueryCarriesPickedStream() throws {
        let base = try channel("https://addon.example/stream/tv/sky.json")
        XCTAssertNil(APIClient.shared.liveStartQuery(base, programTitle: nil)["stremioStreamIndex"])
        var picked = base
        picked.stremioStreamIndex = 2
        XCTAssertEqual(APIClient.shared.liveStartQuery(picked, programTitle: nil)["stremioStreamIndex"], "2")
    }
}
