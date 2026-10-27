import XCTest
@testable import StrmrTV

/// Settings › Playback › Audio Format: Lossless puts TrueHD, then DTS / FLAC / PCM, ahead of the
/// server's E-AC-3-first order, in the player's pick and the source list's defaults alike.
final class LosslessAudioTests: XCTestCase {
    private typealias C = ClientTrackSelector

    private func stream(_ index: Int, _ language: String, _ codec: String, _ title: String = "") -> C.Stream {
        C.Stream(index: index, language: language, title: title, codec: codec, forced: false)
    }

    private lazy var remux = [
        stream(1, "eng", "eac3", "English DD+ Atmos"), stream(2, "eng", "truehd", "English TrueHD Atmos 7.1"),
        stream(3, "eng", "ac3", "Commentary"), stream(4, "fre", "eac3"), stream(5, "fre", "dts", "French DTS-HD MA"),
    ]

    func testCompatibleKeepsTheServerOrder() {
        XCTAssertEqual(C.findAudio(remux, preferred: "eng"), 1)
        XCTAssertEqual(C.findAudio(remux, preferred: "fre"), 4)
    }

    func testLosslessPrefersTrueHDThenDTS() {
        XCTAssertEqual(C.findAudio(remux, preferred: "eng", lossless: true), 2)
        XCTAssertEqual(C.findAudio(remux, preferred: "fre", lossless: true), 5)
        XCTAssertEqual(C.findAllowedAudio(remux, allowed: ["fre", "eng"], preferred: "", lossless: true), 5)
    }

    func testLosslessFallsBackToTheUsualOrder() {
        let lossy = [stream(1, "eng", "aac"), stream(2, "eng", "eac3")]
        XCTAssertEqual(C.findAudio(lossy, preferred: "eng", lossless: true), 2)
    }

    func testLosslessSkipsCommentaryTrueHD() {
        let tracks = [stream(1, "eng", "eac3"), stream(2, "eng", "truehd", "Director's Commentary")]
        XCTAssertEqual(C.findAudio(tracks, preferred: "eng", lossless: true), 1)
    }

    func testSelectCarriesThePreference() {
        let preferences = C.Preferences(audioLanguage: "eng", subtitleMode: "off", losslessAudio: true)
        XCTAssertEqual(C.select(audio: remux, subtitles: [], preferences: preferences).audio?.streamIndex, 2)
    }

    func testSourceListDefaultsFollowThePreference() {
        let audio = [
            ProbedAudioTrack(index: 1, language: "eng", codec: "eac3"),
            ProbedAudioTrack(index: 2, language: "eng", codec: "truehd", title: "English Dolby Atmos 7.1"),
        ]
        XCTAssertEqual(ManualTrackSelection.defaultAudio(audio, preferredLanguage: "eng"), 1)
        XCTAssertEqual(ManualTrackSelection.defaultAudio(audio, preferredLanguage: "eng", lossless: true), 2)
    }
}
