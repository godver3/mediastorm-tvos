import XCTest
@testable import StrmrTV

/// The sports stream picker's Stremio expansion: one row per addon stream, repeats dropped,
/// and when a single strong match plays by itself.
final class SportsStreamOptionsTests: XCTestCase {
    private let addon = "https://addon.example/stream/tv/espn.json"
    private let plain = "https://provider.example/live/1.ts"

    private func match(_ url: String, id: String = "c1", name: String = "ESPN", source: String = "s",
                       tier: String = "strong") -> SportsStreamMatch {
        SportsStreamMatch(channelId: id, channelName: name, channelUrl: url, channelLogo: nil, channelTvgId: nil,
                          sourceId: source, sourceName: "Source", programTitle: nil, confidence: 0.9,
                          confidenceTier: tier, matchReason: nil)
    }

    private func stream(_ index: Int, _ label: String = "", name: String? = nil, title: String? = nil) -> LiveStremioStream {
        LiveStremioStream(index: index, label: label, name: name, title: title, description: nil)
    }

    func testLabelFallsBackToTitleNameThenFeed() {
        XCTAssertEqual(SportsStreamOptions.label(stream(0, "HD")), "HD")
        XCTAssertEqual(SportsStreamOptions.label(stream(0, " ", name: "Addon", title: "1080p")), "1080p")
        XCTAssertEqual(SportsStreamOptions.label(stream(0, "", name: "Addon")), "Addon")
        XCTAssertEqual(SportsStreamOptions.label(stream(2)), "Feed 3")
    }

    func testStremioChannelExpandsInAddonOrder() {
        let matches = [match(addon), match(plain, id: "c2", name: "TSN", tier: "possible")]
        let rows = SportsStreamOptions.rows(matches, lookups: [addon: .loaded([stream(3, "FHD"), stream(0, "SD")])])
        XCTAssertEqual(rows.map(\.match.title), ["ESPN · FHD", "ESPN · SD", "TSN"])
        XCTAssertEqual(rows.map(\.match.stremioStreamIndex), [3, 0, nil])
        XCTAssertEqual(rows.map(\.match.channel.stremioStreamIndex), [3, 0, nil])
        XCTAssertTrue(rows[0].match.isStrong)
        XCTAssertEqual(rows[0].match.sourceName, "Source")
        XCTAssertEqual(rows[0].match.confidence, 0.9)
        XCTAssertEqual(rows[0].match.channel.name, "ESPN")
        XCTAssertFalse(rows.contains(where: \.loading))
        // The first stream keeps the channel row's identity, so focus stays on it as it expands.
        XCTAssertEqual(rows[0].id, matches[0].id)
        XCTAssertNotEqual(rows[1].id, rows[0].id)
    }

    func testPendingFailedAndEmptyKeepThePlainRow() {
        let m = [match(addon)]
        XCTAssertEqual(SportsStreamOptions.rows(m, lookups: [:]).map(\.loading), [true])
        XCTAssertEqual(SportsStreamOptions.rows(m, lookups: [addon: .pending]).map(\.loading), [true])
        for lookup in [SportsStreamLookup.failed, .loaded([])] {
            let rows = SportsStreamOptions.rows(m, lookups: [addon: lookup])
            XCTAssertEqual(rows.count, 1)
            XCTAssertFalse(rows[0].loading)
            XCTAssertNil(rows[0].match.stremioStreamIndex)
            XCTAssertEqual(rows[0].match.title, "ESPN")
        }
    }

    func testDuplicatesDropped() {
        // The same addon under two channel entries of one source, and a repeated stream index.
        let matches = [match(addon), match(addon, id: "c9", name: "ESPN Alt")]
        let rows = SportsStreamOptions.rows(matches, lookups: [addon: .loaded([stream(0, "A"), stream(0, "A again"), stream(1, "B")])])
        XCTAssertEqual(rows.map(\.match.title), ["ESPN · A", "ESPN · B"])
        // Another source's copy of the URL stays.
        let other = SportsStreamOptions.rows([match(addon), match(addon, source: "t")], lookups: [addon: .loaded([stream(0, "A")])])
        XCTAssertEqual(other.count, 2)
        XCTAssertEqual(SportsStreamOptions.lookupURLs([match(addon), match(plain), match(addon, id: "c3")]), [addon])
    }

    private func group(_ primary: SportsStreamMatch, alternatives: [SportsStreamMatch] = []) -> SportsStreamGroup {
        SportsStreamGroup(confidenceTier: "strong", primary: primary, alternatives: alternatives)
    }

    func testAutoPlayPlainChannelPlaysAtOnce() {
        let g = [group(match(plain))]
        XCTAssertEqual(SportsStreamOptions.autoPlay(live: true, broad: false, groups: g, lookups: [:]), .play(match(plain)))
        XCTAssertEqual(SportsStreamOptions.autoPlay(live: false, broad: false, groups: g, lookups: [:]), SportsStreamAutoPlay.none)
        XCTAssertEqual(SportsStreamOptions.autoPlay(live: true, broad: true, groups: g, lookups: [:]), SportsStreamAutoPlay.none)
        XCTAssertEqual(SportsStreamOptions.autoPlay(live: true, broad: false, groups: [group(match(plain), alternatives: [match(addon)])],
                                                    lookups: [:]), SportsStreamAutoPlay.none)
    }

    func testAutoPlayStremioWaitsForItsStreams() {
        let g = [group(match(addon))]
        func decide(_ lookup: SportsStreamLookup?) -> SportsStreamAutoPlay {
            SportsStreamOptions.autoPlay(live: true, broad: false, groups: g, lookups: lookup.map { [addon: $0] } ?? [:])
        }
        XCTAssertEqual(decide(nil), .wait)
        XCTAssertEqual(decide(.pending), .wait)
        XCTAssertEqual(decide(.failed), .play(match(addon)))
        guard case let .play(one) = decide(.loaded([stream(4, "Only")])) else { return XCTFail("expected play") }
        XCTAssertEqual(one.stremioStreamIndex, 4)
        XCTAssertEqual(one.channel.stremioStreamIndex, 4)
        XCTAssertEqual(decide(.loaded([stream(0), stream(1)])), SportsStreamAutoPlay.none)
        XCTAssertEqual(decide(.loaded([])), .play(match(addon)))
    }

    @MainActor
    func testLookupsRunAtMostFourAtOnce() async {
        var running = 0, peak = 0
        let lookups = SportsStreamLookups { channel in
            running += 1
            peak = max(peak, running)
            try await Task.sleep(for: .milliseconds(20))
            running -= 1
            if channel.url.contains("bad") { throw URLError(.badServerResponse) }
            return [LiveStremioStream(index: 0, label: "A", name: nil, title: nil, description: nil)]
        }
        let urls = (0..<7).map { "https://addon.example/stream/tv/\($0).json" } + ["https://bad.example/stream/tv/x.json"]
        await lookups.run(urls.enumerated().map { match($0.element, id: "c\($0.offset)") })
        XCTAssertLessThanOrEqual(peak, 4)
        XCTAssertEqual(lookups.states.count, 8)
        XCTAssertEqual(lookups.states["https://bad.example/stream/tv/x.json"], .failed)
        XCTAssertEqual(lookups.states[urls[0]], .loaded([LiveStremioStream(index: 0, label: "A", name: nil, title: nil, description: nil)]))
    }
}
