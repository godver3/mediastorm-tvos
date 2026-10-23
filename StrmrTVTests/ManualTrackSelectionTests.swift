import XCTest
@testable import StrmrTV

/// The Expo manual picker's track defaults (`manual-selection.tsx`: `findSelectedAudioTrack`,
/// `findSelectedSubtitleTrack`), `player-language-filter.ts` and the hand-off into
/// `TrackPreferences`.
final class ManualTrackSelectionTests: XCTestCase {
    private typealias S = ManualTrackSelection

    private let audio = [
        ProbedAudioTrack(index: 1, language: "eng", codec: "truehd", title: "English Dolby Atmos 7.1"),
        ProbedAudioTrack(index: 2, language: "eng", codec: "ac3", title: "Commentary"),
        ProbedAudioTrack(index: 3, language: "eng", codec: "eac3"),
        ProbedAudioTrack(index: 4, language: "fre", codec: "ac3"),
    ]

    private let subtitles = [
        ProbedSubtitleTrack(index: 5, language: "eng", codec: "subrip", forced: true),
        ProbedSubtitleTrack(index: 6, language: "eng", codec: "subrip"),
        ProbedSubtitleTrack(index: 7, language: "eng", codec: "hdmv_pgs_subtitle", title: "English SDH", isBitmap: true),
        ProbedSubtitleTrack(index: 8, language: "fre", codec: "subrip"),
    ]

    // MARK: Audio

    func testAudioPrefersCompatibleCodecWithoutCommentary() {
        XCTAssertEqual(S.defaultAudio(audio, preferredLanguage: "eng"), 3)
        XCTAssertEqual(S.defaultAudio(audio, preferredLanguage: "fre"), 4)
    }

    func testAudioFallsBackToCommentaryThenTrueHD() {
        let onlyCommentary = [audio[0], audio[1]]
        // Pass 3 (TrueHD, no commentary) comes before the commentary passes.
        XCTAssertEqual(S.defaultAudio(onlyCommentary, preferredLanguage: "eng"), 1)
        XCTAssertEqual(S.defaultAudio([audio[1]], preferredLanguage: "eng"), 2)
    }

    func testAudioWithoutPreferenceOrMatchTakesFirstCompatible() {
        XCTAssertEqual(S.defaultAudio(audio, preferredLanguage: ""), 3)
        XCTAssertEqual(S.defaultAudio(audio, preferredLanguage: "jpn"), 3)
        XCTAssertEqual(S.defaultAudio([audio[0]], preferredLanguage: "jpn"), 1)
        XCTAssertNil(S.defaultAudio([], preferredLanguage: "eng"))
    }

    func testLanguageMatchIsLoose() {
        XCTAssertTrue(S.matchesLanguage("en", nil, "eng"))
        XCTAssertTrue(S.matchesLanguage(nil, "English", "english"))
        XCTAssertFalse(S.matchesLanguage("fre", "French", "eng"))
        XCTAssertFalse(S.matchesLanguage("eng", nil, ""))
    }

    // MARK: Subtitles

    func testSubtitleOnPrefersSDHThenRegularThenForced() {
        XCTAssertEqual(S.defaultSubtitle(subtitles, language: "eng", mode: "on").index, 7)
        XCTAssertEqual(S.defaultSubtitle([subtitles[0], subtitles[1]], language: "eng", mode: "on").index, 6)
        XCTAssertEqual(S.defaultSubtitle([subtitles[0]], language: "eng", mode: "on").index, 5)
    }

    func testSubtitleModes() {
        XCTAssertNil(S.defaultSubtitle(subtitles, language: "eng", mode: "off").index)
        XCTAssertEqual(S.defaultSubtitle(subtitles, language: "eng", mode: "forced-only").index, 5)
        XCTAssertNil(S.defaultSubtitle(subtitles, language: "fre", mode: "forced-only").index)
        XCTAssertNil(S.defaultSubtitle(subtitles, language: "", mode: "on").index)
    }

    func testSubtitleSearchesOnlineWhenNothingMatches() {
        let none = S.defaultSubtitle(subtitles, language: "spa", mode: "on")
        XCTAssertNil(none.index)
        XCTAssertTrue(none.searchesOnline)
        XCTAssertTrue(S.defaultSubtitle([], language: "eng", mode: "on").searchesOnline)
        XCTAssertFalse(S.defaultSubtitle([], language: "eng", mode: "forced-only").searchesOnline)
    }

    // MARK: Allowed languages

    func testAllowedLanguagesKeepUnknownAndFallBackToAll() {
        let tracks: [ProbedAudioTrack] = [
            .init(index: 1, language: "eng"), .init(index: 2, language: "fre"),
            .init(index: 3, language: "und"), .init(index: 4, language: nil),
        ]
        let allowed = S.filterAllowed(tracks, language: \.language, allowed: ["en"]).map(\.index)
        XCTAssertEqual(allowed, [1, 4], "`und` is a language code, not unknown (as in Expo)")
        XCTAssertEqual(S.filterAllowed(tracks, language: \.language, allowed: ["jpn"]).count, 4)
        XCTAssertEqual(S.filterAllowed(tracks, language: \.language, allowed: []).count, 4)
        XCTAssertEqual(S.canonicalLanguage("French"), "fra")
        XCTAssertEqual(S.canonicalLanguage("pt-BR"), "por")
        XCTAssertNil(S.canonicalLanguage(""))
    }

    // MARK: Into the player

    private let server = TrackSelection(
        audio: SelectedTrack(streamIndex: 3, typeIndex: 2, language: "eng", languageCode: "eng", languageIndex: 2,
                             languageCount: 3, codec: "eac3", title: nil, forced: nil, bitmap: nil),
        subtitle: nil, textSubtitle: nil, audioLanguage: "eng", subtitleLanguage: "eng", subtitleMode: "on")

    func testPicksOverrideTheServerSelection() {
        let overrides = ManualTrackOverrides(audioTrack: 1, subtitleTrack: 8)
        let selection = S.apply(overrides, to: server, audio: audio, subtitles: subtitles)
        XCTAssertEqual(selection.audio?.streamIndex, 1)
        XCTAssertEqual(selection.audio?.typeIndex, 0)
        XCTAssertEqual(selection.subtitle?.streamIndex, 8)
        XCTAssertEqual(selection.subtitle?.typeIndex, 3)
        XCTAssertEqual(selection.subtitle?.languageIndex, 0)
        XCTAssertEqual(selection.textSubtitle?.streamIndex, 8)
        XCTAssertEqual(selection.subtitleLanguage, "fre")
        XCTAssertEqual(selection.subtitleMode, "on")
    }

    func testOffAndUntouchedFields() {
        let off = S.apply(ManualTrackOverrides(subtitleTrack: ManualTrackOverrides.off), to: server,
                          audio: audio, subtitles: subtitles)
        XCTAssertEqual(off.audio?.streamIndex, 3, "audio left at the server's pick")
        XCTAssertNil(off.subtitle)
        XCTAssertEqual(off.subtitleMode, "off")
        XCTAssertTrue(TrackPreferences(selection: off).subtitlesExplicitlyOff)
    }

    func testPickedSubtitleTurnsSubtitlesOnWhenTheServerHadThemOff() {
        let quiet = TrackSelection(audio: nil, subtitle: nil, textSubtitle: nil, audioLanguage: nil,
                                   subtitleLanguage: nil, subtitleMode: "off")
        let bitmap = S.apply(ManualTrackOverrides(subtitleTrack: 7), to: quiet, audio: audio, subtitles: subtitles)
        XCTAssertEqual(bitmap.subtitle?.streamIndex, 7)
        XCTAssertNil(bitmap.textSubtitle)
        XCTAssertEqual(bitmap.subtitleMode, "on")
        XCTAssertEqual(S.apply(ManualTrackOverrides(subtitleTrack: 5), to: nil, audio: audio,
                               subtitles: subtitles).subtitleMode, "forced-only")
    }

    func testPicksAreContainerIndexesNotPositions() {
        // A pick that isn't in the probe's list leaves the server's choice alone.
        let unknown = S.apply(ManualTrackOverrides(audioTrack: 0), to: server, audio: audio, subtitles: subtitles)
        XCTAssertEqual(unknown.audio?.streamIndex, 3)
    }
}
