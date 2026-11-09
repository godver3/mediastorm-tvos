#if os(iOS)
import Foundation

/// A screen the phone can hand playback to: a Chromecast (Google Cast SDK) or a DLNA
/// MediaRenderer (SSDP + UPnP AVTransport).
struct CastDevice: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case googleCast, dlna

        var label: String {
            switch self {
            case .googleCast: String(localized: "Chromecast")
            case .dlna: String(localized: "DLNA")
            }
        }
    }

    /// `cast:<device id>` or `dlna:<UDN>`, so the two lists never collide.
    let id: String
    let name: String
    let model: String?
    let kind: Kind
    /// The device's LAN address, when known (shown under the name).
    let address: String?

    var detail: String {
        [model.flatMap { $0.isEmpty || $0 == name ? nil : $0 }, kind.label].compactMap { $0 }.joined(separator: " · ")
    }
}

/// What a receiver reports about the media it is playing.
struct CastPlaybackState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case loading, playing, paused, buffering, idle
        /// The receiver reached the end of the media on its own.
        case finished
    }

    var phase: Phase = .loading
    var position: Double = 0
    /// 0 while the receiver doesn't know.
    var duration: Double = 0
    /// 0...1, nil when the device doesn't say.
    var volume: Float?

    var isPlaying: Bool { phase == .playing || phase == .buffering || phase == .loading }
}

/// The stream a receiver is told to fetch, with what it shows while it plays.
struct CastMedia: Sendable {
    let url: URL
    let contentType: String
    let title: String
    let subtitle: String?
    let posterURL: URL?
    /// Known up front (HLS session, library file), else nil.
    let duration: Double?
    /// Where to start, in the media's own timeline.
    let startPosition: Double
    /// Subtitle rendition to switch on (ISO 639 language), Chromecast only.
    var subtitleLanguage: String?
    /// DLNA: the `res@protocolInfo` the renderer accepted for this URL.
    var protocolInfo: String?
    /// DLNA's progressive MPEG-TS rung has no byte offsets, so no Seek.
    var seekable = true
    /// A live channel: an endless stream with no timeline (Cast `streamType` LIVE, no start
    /// time or duration sent).
    var isLive = false
}

/// One live connection to a receiver. Every call is a network round trip.
@MainActor
protocol CastTransport: AnyObject {
    var device: CastDevice { get }
    /// Progressive transcodes (DLNA's MPEG-TS rung) cannot seek.
    var canSeek: Bool { get }
    func load(_ media: CastMedia) async throws
    func play() async throws
    func pause() async throws
    func seek(to seconds: Double) async throws
    func setVolume(_ volume: Float) async throws
    /// nil when the receiver did not answer.
    func status() async -> CastPlaybackState?
    /// Stops playback on the receiver and lets it go.
    func stop() async
}

struct CastError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
#endif
