import XCTest
@testable import StrmrTV

/// The in-player Switch Source list: rows, the current-source match, and the
/// languages carried onto the chosen source.
final class SourceSwitchTests: XCTestCase {
    private func result(_ index: Int, title: String, guid: String? = nil, service: String = "usenet",
                        size: Int64 = 0, attrs: [String: Any] = [:], health: String? = nil) -> SourceResult {
        var raw: [String: Any] = ["title": title, "serviceType": service, "indexer": "NZBGeek", "sizeBytes": size,
                                  "attributes": attrs]
        if let guid { raw["guid"] = guid }
        if let health { raw["sourceHealth"] = ["state": health] }
        return SourceResult(raw, index: index)!
    }

    /// Both lists take the source picker's order (the server's rank), whatever order the
    /// results arrive in, so Switch Source matches the details page's list.
    func testRowsFollowTheSourcePickerOrder() {
        let results = [result(2, title: "C"), result(0, title: "A"), result(1, title: "B", guid: "b")]
        XCTAssertEqual(SourceSearch.ordered(results).map(\.index), [0, 1, 2])
        let options = SourceSwitch.options(results, health: [:], current: .init(guid: "b"))
        XCTAssertEqual(options.map(\.resultIndex), [0, 1, 2])
        XCTAssertEqual(options.firstIndex(where: \.isCurrent), 1)
    }

    func testQueryMatchesTheSourcePicker() {
        XCTAssertEqual(SourceSwitch.query(name: "Show", year: 2020, episode: (1, 2)), "Show S01E02")
        XCTAssertEqual(SourceSwitch.query(name: "Movie", year: 2024, episode: nil), "Movie 2024")
        XCTAssertEqual(SourceSwitch.query(name: "Movie", year: nil, episode: nil), "Movie")
    }

    func testCurrentMarkedByGuidOrReleaseName() {
        let results = [result(0, title: "Movie.2024.2160p.DV", guid: "a"), result(1, title: "Movie.2024.1080p", guid: "b")]
        var options = SourceSwitch.options(results, health: [:], current: .init(guid: "b"))
        XCTAssertEqual(options.map(\.isCurrent), [false, true])
        options = SourceSwitch.options(results, health: [:], current: .init(releaseName: "movie.2024.2160p.dv.mkv"))
        XCTAssertEqual(options.map(\.isCurrent), [true, false])
        options = SourceSwitch.options(results, health: [:], current: .init(streamPath: "/debrid/rd/Movie.2024.1080p/file.mkv"))
        XCTAssertEqual(options.map(\.isCurrent), [false, true])
    }

    func testMissingCurrentLeadsAsItsOwnRow() {
        let options = SourceSwitch.options([result(0, title: "Other")], health: [:],
                                           current: .init(releaseName: "Playing.Release"))
        XCTAssertEqual(options.count, 2)
        XCTAssertEqual(options[0], SourceSwitch.Option(resultIndex: nil, title: "Playing.Release",
                                                       detail: "Playing now", isCurrent: true))
        XCTAssertFalse(options[1].isCurrent)
    }

    func testDetailShowsResolutionHDRSizeProviderAndHealth() {
        let r = result(3, title: "X", size: 1_000_000_000, attrs: ["resolution": "2160p", "hasDV": "true", "hdr": "HDR10"],
                       health: "pending")
        XCTAssertTrue(SourceSwitch.detail(r, health: SourceHealth(state: "healthy", token: nil))
            .hasPrefix("4K · DV · HDR · "))
        XCTAssertTrue(SourceSwitch.detail(r, health: SourceHealth(state: "healthy", token: nil)).hasSuffix("Usenet · Healthy"))
        let options = SourceSwitch.options([r], health: [3: SourceHealth(state: "cached", token: nil)], current: .init())
        XCTAssertTrue(options[1].detail.hasSuffix("Cached"), "a resolved check wins over the search's pending state")
        let debrid = result(4, title: "Y", service: "debrid", attrs: ["tracker": "RARBG"])
        XCTAssertEqual(SourceSwitch.detail(debrid, health: SourceHealth(state: "not_cached", token: nil)), "RARBG · Not Cached")
    }

    func testCarryPicksAudioByLanguageSkippingCommentary() {
        let carry = TrackCarry(audioLanguage: "eng", subtitle: .unchanged)
        let tracks = [TrackCarry.Track(id: 1, language: "fre"), TrackCarry.Track(id: 2, language: "en", isCommentary: true),
                      TrackCarry.Track(id: 3, language: "eng")]
        XCTAssertEqual(carry.audioTrackID(in: tracks), 3)
        XCTAssertNil(TrackCarry(audioLanguage: "jpn", subtitle: .unchanged).audioTrackID(in: tracks))
        XCTAssertNil(TrackCarry(audioLanguage: nil, subtitle: .unchanged).audioTrackID(in: tracks))
    }

    func testCarrySubtitleOffLanguageOrUnchanged() {
        let tracks = [TrackCarry.Track(id: 5, language: "eng", isForced: true), TrackCarry.Track(id: 6, language: "eng")]
        XCTAssertEqual(TrackCarry(audioLanguage: nil, subtitle: .off).subtitleTrackID(in: tracks), .some(nil))
        XCTAssertEqual(TrackCarry(audioLanguage: nil, subtitle: .language("en", forced: false)).subtitleTrackID(in: tracks), .some(6))
        XCTAssertEqual(TrackCarry(audioLanguage: nil, subtitle: .language("en", forced: true)).subtitleTrackID(in: tracks), .some(5))
        XCTAssertNil(TrackCarry(audioLanguage: nil, subtitle: .language("spa", forced: false)).subtitleTrackID(in: tracks))
        XCTAssertNil(TrackCarry(audioLanguage: nil, subtitle: .unchanged).subtitleTrackID(in: tracks))
    }
}
