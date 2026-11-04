import XCTest
@testable import StrmrTV

/// Subtitles › Foreign Audio: forced subtitles when the audio is in the viewer's language, full
/// ones when it is not, as the server's `trackselect.ResolveForeignAudioMode`.
final class ForeignAudioSubtitleTests: XCTestCase {
    private typealias C = ClientTrackSelector

    private func stream(_ index: Int, _ language: String, _ codec: String, _ title: String = "",
                        forced: Bool = false) -> C.Stream {
        C.Stream(index: index, language: language, title: title, codec: codec, forced: forced)
    }

    private lazy var audio = [stream(1, "eng", "eac3"), stream(2, "jpn", "aac")]
    private lazy var subtitles = [
        stream(3, "eng", "subrip", "Forced", forced: true), stream(4, "eng", "subrip"), stream(5, "spa", "subrip"),
    ]

    private func preferences(audio: String?, subtitle: String? = "eng") -> C.Preferences {
        C.Preferences(audioLanguage: audio, subtitleLanguage: subtitle, subtitleMode: C.foreignAudio)
    }

    func testOwnLanguageAudioGetsForcedSubtitles() {
        let selection = C.select(audio: audio, subtitles: subtitles, preferences: preferences(audio: "eng"))
        XCTAssertEqual(selection.audio?.streamIndex, 1)
        XCTAssertEqual(selection.subtitleMode, "forced-only")
        XCTAssertEqual(selection.subtitle?.streamIndex, 3)
        XCTAssertEqual(selection.subtitleModePreference, C.foreignAudio)
    }

    func testForeignAudioGetsFullSubtitles() {
        let selection = C.select(audio: audio, subtitles: subtitles, preferences: preferences(audio: "jpn"))
        XCTAssertEqual(selection.audio?.streamIndex, 2)
        XCTAssertEqual(selection.subtitleMode, "on")
        XCTAssertEqual(selection.subtitle?.streamIndex, 4)
    }

    func testUnmatchedAudioUsesTheFirstTrack() {
        let japanese = [stream(1, "jpn", "aac")]
        let selection = C.select(audio: japanese, subtitles: subtitles, preferences: preferences(audio: "eng"))
        XCTAssertNil(selection.audio)
        XCTAssertEqual(selection.subtitleMode, "on")
        XCTAssertEqual(selection.subtitle?.streamIndex, 4)
    }

    func testResolveMode() {
        XCTAssertEqual(C.resolveMode(audioLanguage: "en", subtitleLanguage: "eng", preferredAudio: nil), "forced-only")
        XCTAssertEqual(C.resolveMode(audioLanguage: "fre", subtitleLanguage: "en", preferredAudio: nil), "on")
        XCTAssertEqual(C.resolveMode(audioLanguage: nil, subtitleLanguage: "eng", preferredAudio: nil), "forced-only")
        XCTAssertEqual(C.resolveMode(audioLanguage: "und", subtitleLanguage: "eng", preferredAudio: nil), "forced-only")
        XCTAssertEqual(C.resolveMode(audioLanguage: "jpn", subtitleLanguage: nil, preferredAudio: "eng"), "on")
        XCTAssertEqual(C.resolveMode(audioLanguage: "jpn", subtitleLanguage: "", preferredAudio: ""), "forced-only")
    }

    func testSourceListDefaultFollowsTheAudio() {
        let probed = [
            ProbedSubtitleTrack(index: 3, language: "eng", codec: "subrip", title: "Forced", forced: true),
            ProbedSubtitleTrack(index: 4, language: "eng", codec: "subrip", title: nil),
        ]
        let S = ManualTrackSelection.self
        XCTAssertEqual(S.defaultSubtitle(probed, language: "eng", mode: C.foreignAudio, audioLanguage: "eng").index, 3)
        XCTAssertEqual(S.defaultSubtitle(probed, language: "eng", mode: C.foreignAudio, audioLanguage: "jpn").index, 4)
        XCTAssertTrue(S.defaultSubtitle([], language: "eng", mode: C.foreignAudio, audioLanguage: "jpn").searchesOnline)
        XCTAssertFalse(S.defaultSubtitle([], language: "eng", mode: C.foreignAudio, audioLanguage: "eng").searchesOnline)
    }

    @MainActor
    func testNormalizeKeepsTheMode() {
        XCTAssertEqual(TrackSettingsStore.normalizeMode("foreign-audio"), C.foreignAudio)
        XCTAssertEqual(TrackSettingsStore.normalizeMode("smart"), C.foreignAudio)
    }
}
