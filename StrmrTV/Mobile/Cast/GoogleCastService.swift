#if os(iOS)
import Foundation
import GoogleCast

/// Google's Cast SDK: discovery of Chromecasts able to run the Default Media Receiver
/// (`CC1AD845`, the receiver the Expo app casts to) and the sender session to one of them.
@MainActor
final class GoogleCastService: NSObject {
    static let shared = GoogleCastService()

    /// Chromecasts on the network, as the SDK lists them.
    private(set) var devices: [CastDevice] = []
    /// Called whenever `devices` changes.
    var onDevicesChanged: (() -> Void)?
    /// Called when the session ends from the receiver's side (another sender took it, TV off).
    var onSessionEnded: (() -> Void)?

    private var isSetUp = false
    private var pendingStart: CheckedContinuation<Void, Error>?
    private let log = AppLog(category: "cast")

    /// Once, at launch. Discovery runs only while a picker is open (`startDiscovery`).
    func setUp() {
        guard !isSetUp else { return }
        isSetUp = true
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        options.disableDiscoveryAutostart = true
        options.startDiscoveryAfterFirstTapOnCastButton = false
        options.stopReceiverApplicationWhenEndingSession = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().discoveryManager.add(self)
        GCKCastContext.sharedInstance().sessionManager.add(self)
    }

    func startDiscovery() {
        setUp()
        let manager = GCKCastContext.sharedInstance().discoveryManager
        manager.passiveScan = false
        manager.startDiscovery()
        refreshDevices()
    }

    func stopDiscovery() {
        guard isSetUp else { return }
        // A passive scan keeps the list warm without the active mDNS traffic.
        GCKCastContext.sharedInstance().discoveryManager.passiveScan = true
    }

    private func refreshDevices() {
        let manager = GCKCastContext.sharedInstance().discoveryManager
        devices = (0..<manager.deviceCount).map { index in
            let device = manager.device(at: index)
            return CastDevice(id: "cast:\(device.deviceID)", name: device.friendlyName ?? device.modelName ?? "Chromecast",
                              model: device.modelName, kind: .googleCast, address: device.networkAddress.ipAddress)
        }.sorted { $0.name < $1.name }
        onDevicesChanged?()
    }

    /// Connects to `device` (launching, or joining, the Default Media Receiver).
    func connect(to device: CastDevice) async throws -> GoogleCastTransport {
        setUp()
        let id = String(device.id.dropFirst("cast:".count))
        let context = GCKCastContext.sharedInstance()
        guard let gck = context.discoveryManager.device(withUniqueID: id)
            ?? (0..<context.discoveryManager.deviceCount).map(context.discoveryManager.device(at:)).first(where: { $0.deviceID == id }) else {
            throw CastError(String(localized: "\(device.name) is no longer on the network."))
        }
        if let current = context.sessionManager.currentCastSession, current.device.deviceID == gck.deviceID,
           current.remoteMediaClient != nil {
            return GoogleCastTransport(device: device, session: current)
        }
        pendingStart?.resume(throwing: CancellationError())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingStart = continuation
            if !context.sessionManager.startSession(with: gck) {
                pendingStart = nil
                continuation.resume(throwing: CastError(String(localized: "Couldn't connect to \(device.name).")))
            }
        }
        guard let session = context.sessionManager.currentCastSession else {
            throw CastError(String(localized: "Couldn't connect to \(device.name)."))
        }
        return GoogleCastTransport(device: device, session: session)
    }

    /// Ends the session and stops the receiver app.
    func disconnect() {
        guard isSetUp else { return }
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
    }
}

extension GoogleCastService: @preconcurrency GCKDiscoveryManagerListener {
    func didUpdateDeviceList() { refreshDevices() }
}

extension GoogleCastService: @preconcurrency GCKSessionManagerListener {
    func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKCastSession) {
        log.notice("cast session started on \(session.device.friendlyName ?? "?")")
        pendingStart?.resume()
        pendingStart = nil
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        log.error("cast session failed: \(error.localizedDescription)")
        pendingStart?.resume(throwing: error)
        pendingStart = nil
    }

    func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        log.notice("cast session ended\(error.map { ": \($0.localizedDescription)" } ?? "")")
        if let pendingStart {
            pendingStart.resume(throwing: error ?? CancellationError())
            self.pendingStart = nil
        }
        onSessionEnded?()
    }
}

/// A connected Chromecast, driven through the session's `GCKRemoteMediaClient`.
@MainActor
final class GoogleCastTransport: NSObject, CastTransport {
    let device: CastDevice
    let session: GCKCastSession
    let canSeek = true
    private var pendingLoad: CheckedContinuation<Void, Error>?
    private var loadRequest: GCKRequest?
    private var subtitleLanguage: String?
    private var appliedSubtitle = false

    init(device: CastDevice, session: GCKCastSession) {
        self.device = device
        self.session = session
    }

    private var client: GCKRemoteMediaClient {
        get throws {
            guard let client = session.remoteMediaClient else { throw CastError(String(localized: "The Chromecast disconnected.")) }
            return client
        }
    }

    func load(_ media: CastMedia) async throws {
        let metadata = GCKMediaMetadata(metadataType: media.isLive ? .generic : media.subtitle == nil ? .movie : .tvShow)
        metadata.setString(media.title, forKey: kGCKMetadataKeyTitle)
        if let subtitle = media.subtitle { metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle) }
        if let poster = media.posterURL {
            // A channel logo is wide, a poster tall.
            metadata.addImage(media.isLive ? GCKImage(url: poster, width: 512, height: 288)
                                           : GCKImage(url: poster, width: 480, height: 720))
        }

        let info = GCKMediaInformationBuilder(contentURL: media.url)
        info.contentID = media.url.absoluteString
        info.contentType = media.contentType
        info.streamType = media.isLive ? .live : .buffered
        info.metadata = metadata
        if !media.isLive, let duration = media.duration, duration > 0 { info.streamDuration = duration }

        let request = GCKMediaLoadRequestDataBuilder()
        request.mediaInformation = info.build()
        request.autoplay = true
        // A channel starts at the live edge, wherever that is.
        if !media.isLive { request.startTime = media.startPosition }
        subtitleLanguage = media.subtitleLanguage
        appliedSubtitle = false

        let client = try client
        client.add(self)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingLoad = continuation
            let sent = client.loadMedia(with: request.build())
            sent.delegate = self
            loadRequest = sent
        }
    }

    func play() async throws { try client.play() }
    func pause() async throws { try client.pause() }

    func seek(to seconds: Double) async throws {
        let options = GCKMediaSeekOptions()
        options.interval = seconds
        options.resumeState = .unchanged
        try client.seek(with: options)
    }

    func setVolume(_ volume: Float) async throws { session.setDeviceVolume(min(max(volume, 0), 1)) }

    func status() async -> CastPlaybackState? {
        guard let client = session.remoteMediaClient, let status = client.mediaStatus else { return nil }
        var state = CastPlaybackState()
        state.position = client.approximateStreamPosition()
        state.duration = status.mediaInformation?.streamDuration ?? 0
        if !state.duration.isFinite { state.duration = 0 }
        state.volume = session.currentDeviceVolume
        switch status.playerState {
        case .playing: state.phase = .playing
        case .paused: state.phase = .paused
        case .buffering: state.phase = .buffering
        case .loading: state.phase = .loading
        case .idle: state.phase = status.idleReason == .finished ? .finished : .idle
        default: state.phase = .loading
        }
        return state
    }

    func stop() async {
        _ = try? client.stop()
        GoogleCastService.shared.disconnect()
    }

    /// A Chromecast lists a default subtitle rendition inactive and never fetches it until a
    /// track is switched on explicitly (the Expo app's `subtitleLanguage`).
    private func applySubtitle(_ status: GCKMediaStatus?) {
        guard !appliedSubtitle, let language = subtitleLanguage,
              let tracks = status?.mediaInformation?.mediaTracks, !tracks.isEmpty else { return }
        appliedSubtitle = true
        let text = tracks.filter { $0.type == .text }
        guard let track = text.first(where: { TrackPreferences.sameLanguage($0.languageCode, language) })
            ?? text.first(where: { $0.name?.localizedCaseInsensitiveContains(language) == true }) else { return }
        session.remoteMediaClient?.setActiveTrackIDs([NSNumber(value: track.identifier)])
    }
}

extension GoogleCastTransport: @preconcurrency GCKRequestDelegate {
    func requestDidComplete(_ request: GCKRequest) {
        guard request === loadRequest else { return }
        loadRequest = nil
        pendingLoad?.resume()
        pendingLoad = nil
    }

    func request(_ request: GCKRequest, didFailWithError error: GCKError) {
        guard request === loadRequest else { return }
        loadRequest = nil
        pendingLoad?.resume(throwing: CastError(String(localized: "The Chromecast couldn't play this stream (\(error.localizedDescription)).")))
        pendingLoad = nil
    }
}

extension GoogleCastTransport: @preconcurrency GCKRemoteMediaClientListener {
    func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        applySubtitle(mediaStatus)
    }
}
#endif
