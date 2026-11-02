import XCTest
@testable import StrmrTV

/// Details › Audio & Subtitles: the prequeue status's lists, release name and the
/// same-stream guard on the picks.
final class PrequeueTracksTests: XCTestCase {
    private func status(_ extra: String = "", path: String = "/debrid/x/Movie.2026.2160p.mkv",
                        episode: String = "") throws -> PrequeueStatus {
        let json = """
        {"prequeueId": "pq_1", "status": "ready", "streamPath": "\(path)", "displayName": "Movie",
         \(episode)
         "audioTracks": [{"index": 1, "language": "eng", "codec": "eac3", "profile": "Dolby Digital Plus + Dolby Atmos"}],
         "subtitleTracks": [
           {"index": 3, "absoluteIndex": 3, "language": "eng", "codec": "subrip"},
           {"index": 1, "absoluteIndex": 4, "language": "eng", "codec": "hdmv_pgs_subtitle", "forced": true, "isBitmap": true}
         ],
         "trackSelection": {"subtitleMode": "on", "audio": {"streamIndex": 1, "typeIndex": 0, "languageIndex": 0, "languageCount": 1},
                            "subtitle": {"streamIndex": 3, "typeIndex": 0, "languageIndex": 0, "languageCount": 2}}
         \(extra)}
        """
        return try JSONDecoder().decode(PrequeueStatus.self, from: Data(json.utf8))
    }

    func testTrackListsUseContainerStreamNumbers() throws {
        let lists = try status().trackLists
        XCTAssertEqual(lists.audio.map(\.index), [1])
        XCTAssertEqual(lists.audio.first?.profile, "Dolby Digital Plus + Dolby Atmos")
        // `absoluteIndex` wins over a list position in `index`.
        XCTAssertEqual(lists.subtitles.map(\.index), [3, 4])
        XCTAssertEqual(lists.subtitles.last?.isBitmap, true)
        XCTAssertEqual(lists.subtitles.last?.isForced, true)
    }

    func testReleaseTitlePrefersTheRelease() throws {
        XCTAssertEqual(try status().releaseTitle, "Movie.2026.2160p.mkv")
        XCTAssertEqual(try status(#", "selectedResult": {"title": "Movie 2026 2160p WEB-DL"}"#).releaseTitle,
                       "Movie 2026 2160p WEB-DL")
        XCTAssertEqual(try status(#", "resultAttributes": {"raw_title": "Raw Name\nsecond line"}"#).releaseTitle,
                       "Raw Name")
        XCTAssertEqual(try status(#", "passthroughName": "AIO Name""#).releaseTitle, "AIO Name")
        XCTAssertEqual(try status(path: "").releaseTitle, "Movie")
    }

    @MainActor
    func testDefaultsAreTheServerSelection() throws {
        let defaults = try status().trackDefaults
        XCTAssertEqual(defaults, TrackDefaults(audio: 1, subtitle: 3, searchesOnline: false))
    }

    func testPicksApplyOnlyToTheSameStreamAndEpisode() throws {
        let pick = PrequeuePick(streamPath: "/debrid/x/Movie.2026.2160p.mkv", episode: nil,
                                pick: ManualTrackPick(overrides: ManualTrackOverrides(subtitleTrack: -1),
                                                      audio: [], subtitles: []))
        XCTAssertTrue(pick.applies(to: try status()))
        XCTAssertFalse(pick.applies(to: try status(path: "/debrid/y/Other.mkv")))
        XCTAssertFalse(pick.applies(to: try status(episode: #""targetEpisode": {"seasonNumber": 1, "episodeNumber": 2},"#)))
    }

    /// Subtitles Off on details, then another episode played: Off still applies.
    @MainActor
    func testSubtitlesOffCarriesToAnotherEpisode() throws {
        let pick = PrequeuePick(streamPath: "/debrid/x/Show.S01E05.mkv",
                                episode: .init(seasonNumber: 1, episodeNumber: 5),
                                pick: ManualTrackPick(overrides: ManualTrackOverrides(subtitleTrack: -1),
                                                      audio: [], subtitles: []))
        let other = try status(path: "/debrid/x/Show.S01E01.mkv",
                               episode: #""targetEpisode": {"seasonNumber": 1, "episodeNumber": 1},"#)
        XCTAssertFalse(pick.applies(to: other))
        let carried = pick.pick(for: other)
        XCTAssertEqual(carried.overrides.subtitleTrack, ManualTrackOverrides.off)
        let selection = carried.selection(over: other.trackSelection)
        XCTAssertEqual(selection.subtitleMode, "off")
        XCTAssertNil(selection.subtitle)
        XCTAssertNil(selection.textSubtitle)
    }

    /// A picked track moves to the other file's track in the same language and kind.
    func testTrackPicksCarryByLanguage() {
        let pick = ManualTrackPick(
            overrides: ManualTrackOverrides(audioTrack: 2, subtitleTrack: 5),
            audio: [ProbedAudioTrack(index: 1, language: "eng"), ProbedAudioTrack(index: 2, language: "fre")],
            subtitles: [ProbedSubtitleTrack(index: 5, language: "spa")])
        let lists = SourceTrackProbe(
            playable: true,
            audio: [ProbedAudioTrack(index: 1, language: "en"), ProbedAudioTrack(index: 3, language: "fra")],
            subtitles: [ProbedSubtitleTrack(index: 7, language: "spa", forced: true),
                        ProbedSubtitleTrack(index: 8, language: "spa")],
            tracksLoading: false, error: nil)
        XCTAssertEqual(pick.carried(to: lists), ManualTrackOverrides(audioTrack: 3, subtitleTrack: 8))
        // A language the other file lacks follows its default.
        let german = ManualTrackPick(overrides: ManualTrackOverrides(subtitleTrack: 5), audio: [],
                                     subtitles: [ProbedSubtitleTrack(index: 5, language: "ger")])
        XCTAssertTrue(german.carried(to: lists).isEmpty)
    }
}
