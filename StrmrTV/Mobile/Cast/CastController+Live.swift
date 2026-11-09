#if os(iOS)
import Foundation

/// A live channel on the TV, as the Expo app's player casts one: the server opens the channel
/// with `/api/live/hls/start?target=cast` (the same query the local tune sends, so the server's
/// stream limits, Stalker resolve and Stremio pick all apply) and the receiver reads it with
/// no timeline: no start position, no duration, no watch progress.
///
/// - Chromecast: always an HLS session (`format=hls`). The cast target re-encodes to H.264 /
///   AAC with segments kept until the receiver has fetched them (it joins ~14 s behind the
///   edge), and the Default Media Receiver is told the stream is LIVE.
/// - DLNA: the channel's own MPEG-TS mux when the source is set to direct (the `/live/stream`
///   proxy, bit exact) and the renderer takes MPEG-TS, else that cast HLS session when the
///   renderer takes HLS. Neither seeks.
///
/// Either session is kept alive every ten seconds and stopped with the cast.
extension CastController {
    /// Casts `channel` to `device`; `program` is what is on now (shown with the channel's name
    /// and logo).
    func startLive(on device: CastDevice, channel: LiveChannel, program: EPGProgram?) async {
        var session = Session(device: device, title: channel.name, subtitle: program?.title, artworkURL: channel.logoURL)
        session.isLive = true
        session.canSeek = false
        log.notice("casting channel \(channel.name) to \(device.name) (\(device.kind.rawValue))")
        await begin(session) { [self] in
            try requireReachableServer()
            switch device.kind {
            case .googleCast:
                let connected = try await GoogleCastService.shared.connect(to: device)
                let opened = try await openLive(channel, program: program, forceHLS: true)
                let type = opened.isDirect ? Self.directLiveContentType(channel) : Self.hlsMime
                return Prepared(transport: connected, media: liveMedia(opened.url, type, channel, program),
                                hlsSessionID: opened.sessionID, playback: nil)
            case .dlna:
                let transport = try dlnaTransport(for: device)
                let built = try await dlnaLiveMedia(for: transport, channel: channel, program: program)
                return Prepared(transport: transport, media: built.media, hlsSessionID: built.hlsSessionID, playback: nil)
            }
        }
    }

    /// `/api/live/hls/start` for a receiver: the stream URL (token in its query) and, for an
    /// HLS session, its id.
    private func openLive(_ channel: LiveChannel, program: EPGProgram?,
                          forceHLS: Bool) async throws -> (url: URL, sessionID: String?, isDirect: Bool) {
        let api = APIClient.shared
        var query = api.liveStartQuery(channel, programTitle: program?.title)
        query["target"] = "cast"
        if forceHLS { query["format"] = "hls" }
        let start: LiveStart = try await api.send("GET", "/api/live/hls/start", query: query, timeout: 60)
        let isDirect = start.isDirect == true
        guard let path = isDirect ? start.streamUrl : start.playlistUrl, !path.isEmpty,
              isDirect || start.sessionId != nil else {
            throw CastError(String(localized: "The server didn't start this channel for the TV."))
        }
        return (try api.mediaURL(apiPath: path), isDirect ? nil : start.sessionId, isDirect)
    }

    private func liveMedia(_ url: URL, _ contentType: String, _ channel: LiveChannel,
                           _ program: EPGProgram?) -> CastMedia {
        var media = CastMedia(url: url, contentType: contentType, title: channel.name, subtitle: program?.title,
                              posterURL: channel.logoURL, duration: nil, startPosition: 0)
        media.isLive = true
        media.seekable = false
        return media
    }

    /// The upstream's own container, for a direct `/live/stream` proxy (the Expo app's
    /// `castContentType`): a playlist when the provider serves one, else what the Default Media
    /// Receiver accepts for a raw mux.
    private static func directLiveContentType(_ channel: LiveChannel) -> String {
        isPlaylist(channel) ? hlsMime : "video/mp4"
    }

    private static func isPlaylist(_ channel: LiveChannel) -> Bool {
        let path = channel.url.split(separator: "?").first.map(String.init)?.lowercased() ?? ""
        return path.hasSuffix(".m3u8")
    }

    /// MPEG-TS as a renderer may list it, unprofiled first; the `_ISO` profile last for the
    /// renderers that name one (the VOD transcode's, which a 2010 BRAVIA needs).
    private static var transportStreamInfos: [String] {
        ["video/vnd.dlna.mpeg-tts", "video/mpeg", "video/mp2t"]
            .map { protocolInfo($0, operation: "00", converted: false) }
            + [protocolInfo("video/mpeg", profile: "AVC_TS_HD_24_AC3_ISO", operation: "00", converted: false)]
    }

    private func dlnaLiveMedia(for transport: DLNATransport, channel: LiveChannel,
                               program: EPGProgram?) async throws -> (media: CastMedia, hlsSessionID: String?) {
        let sinks = await transport.sinkProtocols()
        let hlsInfo = Self.protocolInfo(Self.hlsMime, operation: "00", converted: true)
        let takesHLS = DLNATransport.accepts(sinks, hlsInfo)
        let tsInfo = Self.isPlaylist(channel) ? nil : Self.transportStreamInfos.first { DLNATransport.accepts(sinks, $0) }

        func media(_ url: URL, _ info: String) -> CastMedia {
            var media = liveMedia(url, String(info.split(separator: ":")[2]), channel, program)
            media.protocolInfo = info
            return media
        }

        // 1. The channel as the source is set to open it: direct is the provider's mux untouched.
        if let tsInfo {
            let opened = try await openLive(channel, program: program, forceHLS: false)
            if opened.isDirect {
                log.notice("DLNA live: direct MPEG-TS (\(tsInfo.split(separator: ":")[2]))")
                return (media(opened.url, tsInfo), nil)
            }
            if takesHLS {
                log.notice("DLNA live: HLS session")
                return (media(opened.url, hlsInfo), opened.sessionID)
            }
            if let id = opened.sessionID { await APIClient.shared.stopLiveSession(id) }
        } else if takesHLS {
            // 2. A cast HLS session.
            let opened = try await openLive(channel, program: program, forceHLS: true)
            log.notice("DLNA live: HLS session")
            return (media(opened.url, hlsInfo), opened.sessionID)
        }
        throw CastError(String(localized: "\(transport.device.name) can't play this channel's stream."))
    }
}
#endif
