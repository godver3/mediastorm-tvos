import XCTest
@testable import StrmrTV

/// Subtitles on with no track in the preferred language: an untagged track (blank, `und`,
/// `unknown`) is picked, as the server's `findUntaggedSubtitleTrack`.
final class UntaggedSubtitleTests: XCTestCase {
    private typealias C = ClientTrackSelector

    private func stream(_ index: Int, _ language: String?, _ title: String = "", forced: Bool = false) -> C.Stream {
        C.Stream(index: index, language: language, title: title, codec: "subrip", forced: forced)
    }

    func testUntaggedTrackIsTheFallback() {
        for language in [nil, "", "und", "unknown", "UNK"] as [String?] {
            let tracks = [stream(3, language, "Signs & Songs"), stream(4, language), stream(5, "spa")]
            XCTAssertEqual(C.findSubtitle(tracks, language: "eng", mode: "on", audioLanguage: "eng"), 4,
                           "language \(language ?? "nil")")
        }
    }

    func testTaggedMatchBeatsUntagged() {
        let tracks = [stream(3, "und"), stream(4, "eng")]
        XCTAssertEqual(C.findSubtitle(tracks, language: "eng", mode: "on", audioLanguage: "eng"), 4)
        let forced = [stream(3, "und"), stream(4, "eng", forced: true)]
        XCTAssertEqual(C.findSubtitle(forced, language: "eng", mode: "on", audioLanguage: "eng"), 4)
    }

    func testForcedOnlyUsesOnlyUntaggedForcedTracks() {
        let tracks = [stream(3, "und"), stream(4, "und", forced: true)]
        XCTAssertEqual(C.findSubtitle(tracks, language: "eng", mode: "forced-only", audioLanguage: "eng"), 4)
        XCTAssertEqual(C.findSubtitle([tracks[0]], language: "eng", mode: "forced-only", audioLanguage: "eng"), -1)
    }

    func testUntaggedSpellingsAreOneLanguage() {
        XCTAssertTrue(TrackPreferences.sameLanguage(nil, "und"))
        XCTAssertTrue(TrackPreferences.sameLanguage("", "unknown"))
        XCTAssertFalse(TrackPreferences.sameLanguage(nil, "eng"))
        XCTAssertTrue(TrackPreferences.sameLanguage("fre", "fr"))
    }
}
