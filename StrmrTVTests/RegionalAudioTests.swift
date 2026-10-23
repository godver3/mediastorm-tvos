import XCTest
@testable import StrmrTV

/// Regional dubs (`backend/services/trackselect/region.go`): a region-tagged audio language picks
/// that dub first and falls back to the language.
final class RegionalAudioTests: XCTestCase {
    private typealias C = ClientTrackSelector

    private func stream(_ index: Int, _ language: String, _ title: String, _ codec: String = "eac3") -> C.Stream {
        C.Stream(index: index, language: language, title: title, codec: codec, forced: false)
    }

    // Spider-Man.Brand.New.Day.2026.MULTi.VF2.2160p.WEB.H265-SUPPLY.
    private lazy var spiderMan = [
        stream(1, "fre", "French (France)"), stream(2, "fre", "French (France) AD", "aac"),
        stream(3, "fre", "French (Canadien)"), stream(4, "eng", "English"),
    ]
    private lazy var terminalList = [stream(1, "eng", "VO"), stream(2, "fre", "VFF"), stream(3, "fre", "VFQ")]

    func testRegionalPreferencePicksTheDub() {
        XCTAssertEqual(C.findAudio(terminalList, preferred: "fre"), 2)
        XCTAssertEqual(C.findAudio(terminalList, preferred: "fr-CA"), 3)
        XCTAssertEqual(C.findAudio(terminalList, preferred: "fr-FR"), 2)
        XCTAssertEqual(C.findAudio(spiderMan, preferred: "fr-ca"), 3)
        XCTAssertEqual(C.findAudio(spiderMan, preferred: "fr-FR"), 1)
        XCTAssertEqual(C.findAudio([stream(1, "fre", "VFF"), stream(2, "fre", "FR-CA 5.1")], preferred: "fr-CA"), 2)
        XCTAssertEqual(C.findAudio([stream(1, "spa", "Castellano"), stream(2, "spa", "Latino")], preferred: "es-419"), 2)
        XCTAssertEqual(C.findAudio([stream(1, "por", "Portugal"), stream(2, "por", "Brasileiro")], preferred: "pt-BR"), 2)
    }

    func testRegionalPreferenceFallsBackToTheLanguage() {
        XCTAssertEqual(C.findAudio([stream(1, "eng", ""), stream(2, "fre", "VFF")], preferred: "fr-CA"), 2)
        XCTAssertEqual(C.findAudio([stream(1, "fre", "VFF"), stream(2, "fre", "VFQ Commentary")], preferred: "fr-CA"), 1)
    }

    func testAudioDescriptionRanksWithCommentary() {
        let tracks = [stream(1, "fre", "French (France)", "truehd"), stream(2, "fre", "French (France) AD", "aac")]
        XCTAssertEqual(C.findAudio(tracks, preferred: "fre"), 1)
        XCTAssertTrue(C.isCommentary("Audio Description"))
        XCTAssertFalse(C.isCommentary("Adaptive 5.1"))
    }

    func testManualPanelPreselectsTheDub() {
        let tracks = [
            ProbedAudioTrack(index: 1, language: "eng", codec: "eac3", title: "VO"),
            ProbedAudioTrack(index: 2, language: "fre", codec: "eac3", title: "VFF"),
            ProbedAudioTrack(index: 3, language: "fre", codec: "eac3", title: "VFQ"),
        ]
        XCTAssertEqual(ManualTrackSelection.defaultAudio(tracks, preferredLanguage: "fr-ca"), 3)
        XCTAssertEqual(ManualTrackSelection.defaultAudio(tracks, preferredLanguage: "fre"), 2)
        XCTAssertEqual(ManualTrackSelection.defaultAudio(Array(tracks.prefix(2)), preferredLanguage: "fr-CA"), 2)
    }

    func testVariants() {
        XCTAssertEqual(RegionalAudio.variant("fr-ca")?.name, "French (Canada)")
        XCTAssertNil(RegionalAudio.variant("fre"))
        XCTAssertNil(RegionalAudio.variant("fr-XX"))
        XCTAssertTrue(RegionalAudio.sameVariant("fr-CA", "fre-ca"))
        XCTAssertFalse(RegionalAudio.sameVariant("fr-CA", "fra"))
    }
}
