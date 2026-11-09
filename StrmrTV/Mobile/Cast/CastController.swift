#if os(iOS)
import Combine
import Foundation
import UIKit

/// The phone's one cast session: device discovery for the picker (Chromecasts through the Cast
/// SDK, DLNA renderers over SSDP), starting a cast from a resolved stream, the receiver's state
/// polled every second for the remote, and watch progress reported to the server as the local
/// player does, so Continue Watching follows what plays on the TV.
@MainActor
final class CastController: ObservableObject {
    static let shared = CastController()

    struct Session {
        enum Phase: Equatable {
            case connecting
            case active
            case failed(String)
        }

        let device: CastDevice
        let title: String
        let subtitle: String?
        let artworkURL: URL?
        /// A live channel: no timeline, no seeking, no progress.
        var isLive = false
        var phase: Phase = .connecting
        var state = CastPlaybackState()
        var canSeek = true
    }

    @Published private(set) var chromecasts: [CastDevice] = []
    @Published private(set) var renderers: [CastDevice] = []
    @Published private(set) var isSearching = false
    @Published var session: Session?

    private(set) var dlna: [String: DLNARenderer] = [:]
    var transport: CastTransport?
    /// The title watch progress is reported against; nil for a live channel.
    var playback: (request: PlaybackRequest, path: String)?
    /// The server HLS session the receiver reads: kept alive, stopped with the cast.
    var hlsSessionID: String?
    var pollTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    var startTask: Task<Void, Never>?
    /// Armed by the details page's Cast: the next resolved stream goes to this device.
    var handoff: (device: CastDevice, armed: Date)?
    var handoffWatch: AnyCancellable?
    let log = AppLog(category: "cast")

    private init() {
        GoogleCastService.shared.onDevicesChanged = { [weak self] in
            self?.chromecasts = GoogleCastService.shared.devices
        }
        GoogleCastService.shared.onSessionEnded = { [weak self] in
            guard let self, transport is GoogleCastTransport, case .active = session?.phase else { return }
            Task { await self.finish(reason: "receiver ended the session", stopReceiver: false) }
        }
    }

    // MARK: Discovery

    /// The picker is up: Chromecasts stream in from the SDK, DLNA renderers after one SSDP window.
    func startDiscovery() {
        GoogleCastService.shared.startDiscovery()
        chromecasts = GoogleCastService.shared.devices
        refreshRenderers()
    }

    func stopDiscovery() {
        GoogleCastService.shared.stopDiscovery()
    }

    func refreshRenderers() {
        guard searchTask == nil else { return }
        isSearching = true
        searchTask = Task {
            let found = await DLNADiscovery.discover()
            for renderer in found { dlna[renderer.device.id] = renderer }
            // Keep a renderer added by hand that didn't answer this round's multicast.
            let ids = Set(found.map(\.device.id))
            renderers = (found.map(\.device) + renderers.filter { !ids.contains($0.id) && dlna[$0.id] != nil })
                .sorted { $0.name < $1.name }
            isSearching = false
            searchTask = nil
        }
    }

    /// A renderer typed in by address.
    func addRenderer(host: String) async throws -> CastDevice {
        let renderer = try await DLNADiscovery.probe(host: host)
        dlna[renderer.device.id] = renderer
        renderers = ([renderer.device] + renderers.filter { $0.id != renderer.device.id }).sorted { $0.name < $1.name }
        return renderer.device
    }

    // MARK: Starting

    /// Casts a resolved stream (`path`, as the local player would open it) to `device` from
    /// `position`. `audio` / `subtitle` are container stream indices (nil: the server's pick /
    /// none). Shows the remote at once; a failure is shown there.
    func start(on device: CastDevice, request: PlaybackRequest, path: String, position: Double,
               audio: Int?, subtitle: Int?, subtitleLanguage: String?) async {
        let poster = (request.title.posterURL ?? request.episode?.imageURL).flatMap(Self.absoluteURL)
        let session = Session(device: device, title: request.title.name,
                              subtitle: request.episode.map { [$0.code, $0.name].compactMap { $0 }.joined(separator: " · ") },
                              artworkURL: poster)
        log.notice("casting \(request.displayTitle) to \(device.name) (\(device.kind.rawValue)) from \(Int(position))s")
        await begin(session) { [self] in
            switch device.kind {
            case .googleCast:
                let connected = try await GoogleCastService.shared.connect(to: device)
                let built = try await chromecastMedia(request: request, path: path, position: position,
                                                      audio: audio, subtitle: subtitle,
                                                      subtitleLanguage: subtitleLanguage, poster: poster)
                return Prepared(transport: connected, media: built.media, hlsSessionID: built.hlsSessionID,
                                playback: (request, path))
            case .dlna:
                let dlnaTransport = try dlnaTransport(for: device)
                let built = try await dlnaMedia(for: dlnaTransport, request: request, path: path,
                                                position: position, audio: audio, subtitle: subtitle, poster: poster)
                return Prepared(transport: dlnaTransport, media: built.media, hlsSessionID: built.hlsSessionID,
                                playback: (request, path))
            }
        }
    }

    func dlnaTransport(for device: CastDevice) throws -> DLNATransport {
        guard let renderer = dlna[device.id] else {
            throw CastError(String(localized: "\(device.name) is no longer on the network."))
        }
        return DLNATransport(renderer: renderer)
    }

    static func absoluteURL(_ string: String) -> URL? {
        guard !string.isEmpty else { return nil }
        if string.hasPrefix("http") { return URL(string: string) }
        return try? APIClient.shared.mediaURL(apiPath: string.hasPrefix("/api/") ? String(string.dropFirst(4)) : string)
    }

    // MARK: Controls

    func togglePlayPause() {
        guard let transport, let state = session?.state else { return }
        let playing = state.isPlaying
        session?.state.phase = playing ? .paused : .playing
        Task {
            do { try await (playing ? transport.pause() : transport.play()) } catch { log.error("toggle failed: \(error.localizedDescription)") }
            reportProgress(ended: false)
        }
    }

    func seek(to seconds: Double) {
        guard let transport, session?.canSeek == true, session?.isLive == false else { return }
        let duration = session?.state.duration ?? 0
        let target = duration > 0 ? min(max(0, seconds), duration - 1) : max(0, seconds)
        session?.state.position = target
        Task {
            do { try await transport.seek(to: target) } catch { log.error("seek failed: \(error.localizedDescription)") }
        }
    }

    func skip(by delta: Double) { seek(to: (session?.state.position ?? 0) + delta) }

    func setVolume(_ volume: Float) {
        guard let transport else { return }
        session?.state.volume = volume
        Task { try? await transport.setVolume(volume) }
    }

    /// Stop Casting: the receiver stops, progress is saved, the server's session is let go.
    func stop() {
        Task { await finish(reason: "stopped from the phone", stopReceiver: true) }
    }

    /// Clears a failed attempt off the remote.
    func dismissFailure() {
        if case .failed = session?.phase { session = nil }
    }
}
#endif
