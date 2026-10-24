import AetherEngine
import XCTest
@testable import StrmrTV

/// The player's Stream tab: the source label (service + provider / indexer, or the library)
/// and the video, dynamic-range and audio lines.
final class StreamInfoTests: XCTestCase {
    func testSourceFromServiceAndProvider() {
        XCTAssertEqual(StreamSource.label(path: "/debrid/realdebrid/abc/file.mkv", serviceType: "debrid",
                                          debridProvider: "realdebrid"), "Debrid · Real-Debrid")
        XCTAssertEqual(StreamSource.label(path: "/webdav/streams/x.mkv", serviceType: "usenet", indexer: "NZBGeek"),
                       "Usenet · NZBGeek")
        XCTAssertEqual(StreamSource.label(path: "/webdav/streams/x.mkv", serviceType: "usenet"), "Usenet")
    }

    func testSourceInferredFromPath() {
        XCTAssertEqual(StreamSource.label(path: "/debrid/torbox/123/file.mkv"), "Debrid · TorBox")
        XCTAssertEqual(StreamSource.label(path: "/debrid/Some%20Service/1"), "Debrid · Some Service")
        XCTAssertEqual(StreamSource.label(path: "plexmedia:abc"), "Plex")
        XCTAssertEqual(StreamSource.label(path: "jellyfinmedia:abc"), "Jellyfin")
        XCTAssertEqual(StreamSource.label(path: "localmedia:abc"), "Local")
        XCTAssertEqual(StreamSource.label(path: "/streams/nzb/file.mkv"), "Usenet")
        XCTAssertNil(StreamSource.label(path: nil))
    }

    func testProviderNames() {
        XCTAssertEqual(StreamSource.providerName("Real Debrid"), "Real-Debrid")
        XCTAssertEqual(StreamSource.providerName("debrid-link"), "Debrid-Link")
        XCTAssertEqual(StreamSource.providerName("NewService"), "NewService")
        XCTAssertNil(StreamSource.providerName(" "))
    }

    func testVideoLine() {
        XCTAssertEqual(StreamFormat.video(width: 3840, height: 2160, codec: "hevc", profile: "Main 10",
                                          frameRate: 23.976023, bitrate: 18_400_000),
                       "3840×2160 (4K) · HEVC Main 10 · 23.976 fps · 18.4 Mbps")
        XCTAssertEqual(StreamFormat.video(width: 1920, height: 800, codec: "h264", profile: nil, frameRate: 24,
                                          bitrate: 0),
                       "1920×800 (1080p) · H.264 · 24 fps")
        XCTAssertNil(StreamFormat.video(width: 0, height: 0, codec: nil, profile: nil, frameRate: nil, bitrate: 0))
    }

    func testDynamicRange() {
        XCTAssertEqual(StreamFormat.dynamicRange(source: .dolbyVision, dvProfile: 8, displayed: .dolbyVision),
                       "Dolby Vision Profile 8")
        XCTAssertEqual(StreamFormat.dynamicRange(source: .dolbyVision, dvProfile: 5, displayed: .sdr),
                       "Dolby Vision Profile 5 · Shown as SDR")
        XCTAssertEqual(StreamFormat.dynamicRange(source: .hdr10Plus, dvProfile: nil, displayed: .hdr10Plus), "HDR10+")
        XCTAssertEqual(StreamFormat.dynamicRange(source: .sdr, dvProfile: nil, displayed: .sdr), "SDR")
    }

    func testAudioLine() {
        let atmos = TrackInfo(id: 1, name: "English", codec: "eac3", language: "en", channels: 6, bitrate: 768_000,
                              isDefault: true, isAtmos: true, sampleRate: 48000)
        XCTAssertEqual(StreamFormat.audio(atmos), "E-AC-3 · 5.1 · Atmos · English · 768 kbps · 48 kHz")
        let truehd = TrackInfo(id: 2, name: "", codec: "truehd", language: "und", channels: 8, isDefault: false,
                               profile: "Dolby TrueHD + Dolby Atmos")
        XCTAssertEqual(StreamFormat.audio(truehd), "TrueHD · Dolby TrueHD + Dolby Atmos · 7.1")
        let aac = TrackInfo(id: 3, name: "", codec: "aac", language: nil, channels: 2, isDefault: false, profile: "LC")
        XCTAssertEqual(StreamFormat.audio(aac), "AAC · Stereo")
        XCTAssertNil(StreamFormat.audio(nil))
    }

    func testRowsSkipUnknownValues() {
        let info = StreamInfo(file: "Movie.2024.2160p.mkv", source: "Usenet", video: nil, dynamicRange: "SDR", audio: "")
        XCTAssertEqual(info.rows.map(\.label), ["File", "Dynamic Range", "Source"])
    }
}
