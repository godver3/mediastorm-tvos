#if os(iOS)
import Foundation

/// `GET /api/video/hls/start`: the session id, its playlist path (under `/api`) and the length.
struct CastHLSStart: Decodable {
    let sessionId: String?
    let playlistUrl: String?
    let duration: Double?
}

/// What each kind of receiver is handed, as the Expo app builds it.
///
/// - Chromecast: always a re-encoded HLS session (`cast=true&forceAAC=true`, built from 0, the
///   resume point sent as the LOAD's start time). The Default Media Receiver shows an MKV's video
///   with no audio, and the cast profile forces a keyframe every 2 s, which the backend's
///   fixed-duration playlist relies on.
/// - DLNA: the original file first (bit exact; an LG plays MKV with AC-3 straight), then a
///   transcoded HLS session, then progressive H.264/AC-3 MPEG-TS (`dlnaProfile=avc-ts`) for old
///   renderers, stopping at the first the renderer's Sink protocolInfo accepts.
///
/// A receiver fetches from the server itself, with no headers: the session token rides in the
/// query (`token=`, as on every header-less media URL), and the server must be at an address
/// the TV can reach, which a remote-access (iroh) loopback proxy is not.
extension CastController {
    private static let dlnaFlags = "01700000000000000000000000000000"
    private static let hlsMime = "application/vnd.apple.mpegurl"

    private func requireReachableServer() throws {
        let host = APIClient.shared.baseURL.host?.lowercased() ?? ""
        if host == "localhost" || host == "::1" || host.hasPrefix("127.") {
            throw CastError(String(localized: "Casting needs the server's network address. Over remote access the TV can't reach the server; connect on your home network first."))
        }
    }

    /// Starts a server HLS session for the stream.
    private func startHLS(path: String, request: PlaybackRequest, cast: Bool, audio: Int?, subtitle: Int?) async throws -> CastHLSStart {
        let api = APIClient.shared
        var query = request.streamMetadata(path: path)
        query["path"] = path
        query["start"] = "0"
        query["profileId"] = api.profileID
        if let name = api.profileName, !name.isEmpty { query["profileName"] = name }
        if cast {
            query["cast"] = "true"
            query["forceAAC"] = "true"
        }
        if let audio, audio >= 0 { query["audioTrack"] = String(audio) }
        if let subtitle, subtitle >= 0 { query["subtitleTrack"] = String(subtitle) }
        let start: CastHLSStart = try await api.send("GET", "/api/video/hls/start", query: query, timeout: 90)
        guard let playlist = start.playlistUrl, !playlist.isEmpty, start.sessionId != nil else {
            throw CastError(String(localized: "The server didn't start a stream for the TV."))
        }
        return start
    }

    /// A resume given as a percentage, once the length is known.
    private func startPosition(_ request: PlaybackRequest, position: Double, duration: Double?) -> Double {
        if position > 0 { return position }
        if case let .percent(percent)? = request.start, let duration, duration > 0 { return duration * percent / 100 }
        return 0
    }

    func chromecastMedia(request: PlaybackRequest, path: String, position: Double, audio: Int?, subtitle: Int?,
                         subtitleLanguage: String?, poster: URL?) async throws -> (media: CastMedia, hlsSessionID: String?) {
        try requireReachableServer()
        let start = try await startHLS(path: path, request: request, cast: true, audio: audio, subtitle: subtitle)
        let url = try APIClient.shared.mediaURL(apiPath: start.playlistUrl ?? "")
        let duration = start.duration.flatMap { $0 > 0 ? $0 : nil }
        var media = CastMedia(url: url, contentType: Self.hlsMime, title: request.title.name,
                              subtitle: request.episode.map { [$0.code, $0.name].compactMap { $0 }.joined(separator: " · ") },
                              posterURL: poster, duration: duration,
                              startPosition: startPosition(request, position: position, duration: duration))
        media.subtitleLanguage = subtitle == nil ? nil : subtitleLanguage
        return (media, start.sessionId)
    }

    /// The direct stream with the token in its query (a renderer sends no headers).
    private func directURL(request: PlaybackRequest, path: String, extra: [String: String] = [:]) -> URL {
        let api = APIClient.shared
        var comps = URLComponents(url: api.streamURL(for: path, metadata: request.streamMetadata(path: path)),
                                  resolvingAgainstBaseURL: false)!
        var items = comps.percentEncodedQueryItems ?? []
        var added = extra
        if let token = api.token { added["token"] = token }
        for (name, value) in added.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: name, value: APIClient.segment(value)))
        }
        comps.percentEncodedQueryItems = items
        return comps.url!
    }

    private static func mimes(forPath path: String) -> [String] {
        let name = path.split(separator: "?").first.map(String.init) ?? path
        switch (name as NSString).pathExtension.lowercased() {
        case "mkv": return ["video/x-matroska", "video/x-mkv", "video/mp4"]
        case "webm": return ["video/webm"]
        case "mov": return ["video/quicktime", "video/mp4"]
        case "ts", "m2ts", "mts": return ["video/vnd.dlna.mpeg-tts", "video/mpeg"]
        case "avi": return ["video/x-msvideo", "video/avi"]
        default: return ["video/mp4"]
        }
    }

    private static func protocolInfo(_ mime: String, profile: String? = nil, operation: String = "01",
                                      converted: Bool) -> String {
        let features = [profile.map { "DLNA.ORG_PN=\($0)" }, "DLNA.ORG_OP=\(operation)",
                        "DLNA.ORG_CI=\(converted ? 1 : 0)", "DLNA.ORG_FLAGS=\(dlnaFlags)"].compactMap { $0 }
        return "http-get:*:\(mime):\(features.joined(separator: ";"))"
    }

    func dlnaMedia(for transport: DLNATransport, request: PlaybackRequest, path: String, position: Double,
                   audio: Int?, subtitle: Int?, poster: URL?) async throws -> (media: CastMedia, hlsSessionID: String?) {
        try requireReachableServer()
        let sinks = await transport.sinkProtocols()
        let title = request.displayTitle
        func media(_ url: URL, _ info: String, duration: Double?, seekable: Bool = true) -> CastMedia {
            var media = CastMedia(url: url, contentType: info.split(separator: ":")[2].description, title: title,
                                  subtitle: request.displaySubtitle, posterURL: poster, duration: duration,
                                  startPosition: startPosition(request, position: position, duration: duration))
            media.protocolInfo = info
            media.seekable = seekable
            return media
        }

        // 1. The original container.
        let direct = directURL(request: request, path: path)
        if let info = Self.mimes(forPath: path).map({ Self.protocolInfo($0, converted: false) })
            .first(where: { DLNATransport.accepts(sinks, $0) }) {
            log.notice("DLNA: direct stream (\(info.split(separator: ":")[2]))")
            return (media(direct, info, duration: await Self.streamDuration(direct)), nil)
        }
        // 2. A transcoded HLS session.
        let hlsInfo = Self.protocolInfo(Self.hlsMime, converted: true)
        if DLNATransport.accepts(sinks, hlsInfo) {
            let start = try await startHLS(path: path, request: request, cast: false, audio: audio, subtitle: subtitle)
            let url = try APIClient.shared.mediaURL(apiPath: start.playlistUrl ?? "")
            log.notice("DLNA: transcoded HLS")
            return (media(url, hlsInfo, duration: start.duration.flatMap { $0 > 0 ? $0 : nil }), start.sessionId)
        }
        // 3. Progressive MPEG-TS, announced as `video/mpeg` with the `_ISO` profile (a Sony BRAVIA
        //    of 2010 plays it only that way). A live mux: no byte offsets, so no Seek.
        let tsInfo = Self.protocolInfo("video/mpeg", profile: "AVC_TS_HD_24_AC3_ISO", operation: "00", converted: true)
        guard DLNATransport.accepts(sinks, tsInfo) else {
            throw CastError(String(localized: "\(transport.device.name) doesn't accept any format the server can send."))
        }
        log.notice("DLNA: progressive MPEG-TS")
        let ts = directURL(request: request, path: path, extra: ["dlnaProfile": "avc-ts"])
        return (media(ts, tsInfo, duration: await Self.streamDuration(direct), seekable: false), nil)
    }

    /// The length the server states on the stream (`Content-Duration`), for renderers that
    /// report none: without it a finished episode can't be told from a stop.
    private static func streamDuration(_ url: URL) async -> Double? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        let header = http.value(forHTTPHeaderField: "Content-Duration") ?? http.value(forHTTPHeaderField: "X-Content-Duration")
        return header.flatMap(Double.init).flatMap { $0 > 0 ? $0 : nil }
    }
}
#endif
