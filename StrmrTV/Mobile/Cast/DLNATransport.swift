#if os(iOS)
import Foundation

/// A DLNA renderer driven over UPnP AVTransport (SetAVTransportURI, Play, Pause, Seek, Stop,
/// GetTransportInfo / GetPositionInfo polling) and RenderingControl (volume), with the Expo
/// bridge's handling of renderers that wedge or answer slowly.
@MainActor
final class DLNATransport: CastTransport {
    let renderer: DLNARenderer
    var device: CastDevice { renderer.device }
    private(set) var canSeek = true
    private var polls = 0
    private var lastVolume: Float?
    private let log = AppLog(category: "dlna")

    init(renderer: DLNARenderer) {
        self.renderer = renderer
    }

    private var av: DLNARenderer.Service { renderer.avTransport }

    // MARK: Media negotiation

    /// The renderer's Sink protocolInfo list (`ConnectionManager.GetProtocolInfo`); nil when it
    /// won't say, in which case the original container is offered as is.
    func sinkProtocols() async -> [String]? {
        guard let manager = renderer.connectionManager,
              let reply = try? await DLNASOAP.call(manager, "GetProtocolInfo", [], timeout: 8) else { return nil }
        let sink = reply.child("Sink")?.text ?? ""
        let entries = sink.split(separator: ",").map { String($0).castTrimmed }.filter { !$0.isEmpty }
        return entries.isEmpty ? nil : entries
    }

    /// Whether a Sink list takes `protocolInfo` (`http-get:*:mime:features`): protocol, network
    /// and MIME type must match, and a sink naming a DLNA profile must name ours.
    static func accepts(_ sinks: [String]?, _ protocolInfo: String) -> Bool {
        guard let sinks else { return true }
        let offered = protocolInfo.split(separator: ":", maxSplits: 3).map(String.init)
        guard offered.count == 4 else { return false }
        let offeredMime = offered[2].lowercased()
        let offeredProfile = profile(in: offered[3])
        return sinks.contains { sink in
            let parts = sink.split(separator: ":", maxSplits: 3).map(String.init)
            guard parts.count == 4, parts[0] == "*" || parts[0] == "http-get", parts[1] == "*" else { return false }
            let mime = parts[2].lowercased()
            let mimeMatches = mime == "*" || mime == "*/*" || mime == offeredMime
                || (mime.hasSuffix("/*") && offeredMime.hasPrefix(String(mime.dropLast())))
            guard mimeMatches else { return false }
            if let required = profile(in: parts[3]) { return required == offeredProfile }
            return true
        }
    }

    private static func profile(in features: String) -> String? {
        features.split(separator: ";").first { $0.hasPrefix("DLNA.ORG_PN=") }.map { String($0.dropFirst(12)) }
    }

    static func didlLite(title: String, url: URL, protocolInfo: String) -> String {
        let mime = protocolInfo.split(separator: ":").dropFirst(2).first.map(String.init) ?? "video/mp4"
        let itemClass = mime.hasPrefix("audio/") ? "object.item.audioItem.musicTrack" : "object.item.videoItem"
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\">"
            + "<item id=\"0\" parentID=\"-1\" restricted=\"1\"><dc:title>\(DLNASOAP.escape(title))</dc:title>"
            + "<upnp:class>\(itemClass)</upnp:class><res protocolInfo=\"\(DLNASOAP.escape(protocolInfo))\">"
            + "\(DLNASOAP.escape(url.absoluteString))</res></item></DIDL-Lite>"
    }

    // MARK: CastTransport

    func load(_ media: CastMedia) async throws {
        let protocolInfo = media.protocolInfo ?? "http-get:*:\(media.contentType):*"
        canSeek = media.seekable
        // A renderer mid-playback (or just finished) need not take new media: LG wedges in
        // TRANSITIONING, Sony answers 701 until stopped. Stop and wait for idle first.
        await settle()
        let metadata = Self.didlLite(title: media.title, url: media.url, protocolInfo: protocolInfo)
        let arguments = [("InstanceID", "0"), ("CurrentURI", media.url.absoluteString), ("CurrentURIMetaData", metadata)]
        do {
            try await DLNASOAP.call(av, "SetAVTransportURI", arguments)
        } catch {
            log.notice("SetAVTransportURI failed, clearing the transport and retrying: \(error.localizedDescription)")
            await settle()
            try await DLNASOAP.call(av, "SetAVTransportURI", arguments)
        }
        do {
            try await play()
        } catch {
            // Opening a large file can leave Play unanswered past the timeout: check the state.
            guard await waitForPlaying() else { throw error }
        }
        if media.startPosition > 1, media.seekable {
            do { try await seek(to: media.startPosition) } catch {
                log.notice("resume seek failed: \(error.localizedDescription)")
            }
        }
    }

    func play() async throws { try await DLNASOAP.call(av, "Play", [("InstanceID", "0"), ("Speed", "1")]) }
    func pause() async throws { try await DLNASOAP.call(av, "Pause", [("InstanceID", "0")]) }

    func seek(to seconds: Double) async throws {
        guard canSeek else { throw CastError(String(localized: "This stream can't seek on this TV.")) }
        try await DLNASOAP.call(av, "Seek", [("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", DLNASOAP.clock(seconds))])
    }

    func setVolume(_ volume: Float) async throws {
        guard let rc = renderer.renderingControl else { throw CastError(String(localized: "This TV has no volume control.")) }
        let level = Int((min(max(volume, 0), 1) * 100).rounded())
        try await DLNASOAP.call(rc, "SetVolume", [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", String(level))],
                                timeout: 8)
        lastVolume = Float(level) / 100
    }

    func status() async -> CastPlaybackState? {
        guard let transport = try? await DLNASOAP.call(av, "GetTransportInfo", [("InstanceID", "0")], timeout: 8) else { return nil }
        let position = try? await DLNASOAP.call(av, "GetPositionInfo", [("InstanceID", "0")], timeout: 8)
        polls += 1
        if polls % 5 == 1, let rc = renderer.renderingControl,
           let reply = try? await DLNASOAP.call(rc, "GetVolume", [("InstanceID", "0"), ("Channel", "Master")], timeout: 8),
           let level = Float(reply.child("CurrentVolume")?.text.castTrimmed ?? "") {
            lastVolume = level / 100
        }
        let state = transport.child("CurrentTransportState")?.text.castTrimmed.uppercased() ?? ""
        var result = CastPlaybackState()
        result.position = DLNASOAP.seconds(position?.child("RelTime")?.text) ?? 0
        result.duration = DLNASOAP.seconds(position?.child("TrackDuration")?.text) ?? 0
        result.volume = lastVolume
        switch state {
        case "PLAYING": result.phase = .playing
        case "PAUSED_PLAYBACK", "PAUSED_RECORDING": result.phase = .paused
        case "TRANSITIONING": result.phase = .buffering
        default: result.phase = .idle  // STOPPED / NO_MEDIA_PRESENT: the controller decides if it finished
        }
        return result
    }

    func stop() async {
        _ = try? await DLNASOAP.call(av, "Stop", [("InstanceID", "0")], timeout: 15)
    }

    // MARK: Recovery

    /// Stops the transport until it reports STOPPED or NO_MEDIA_PRESENT (three tries).
    private func settle() async {
        for _ in 0..<3 {
            _ = try? await DLNASOAP.call(av, "Stop", [("InstanceID", "0")])
            let reply = try? await DLNASOAP.call(av, "GetTransportInfo", [("InstanceID", "0")], timeout: 8)
            let state = reply?.child("CurrentTransportState")?.text.uppercased() ?? ""
            if state.contains("STOPPED") || state.contains("NO_MEDIA_PRESENT") { return }
        }
    }

    /// A stalled start gets another Play every third poll (as a user reaching for the TV
    /// remote would); a position that moves counts as started even in TRANSITIONING.
    private func waitForPlaying() async -> Bool {
        var lastPosition: Double?
        for attempt in 0..<30 {
            try? await Task.sleep(for: .seconds(2))
            guard let state = await status() else { continue }
            if state.phase == .playing { return true }
            if state.phase == .idle { return false }
            if let lastPosition, state.position > lastPosition { return true }
            lastPosition = state.position
            if (attempt + 1) % 3 == 0 { try? await play() }
        }
        return false
    }
}
#endif
