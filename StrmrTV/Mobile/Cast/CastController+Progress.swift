#if os(iOS)
import Foundation

/// The running cast: the receiver polled every second, watch progress every ten (the local
/// player's cadence), the server's HLS session kept warm while a paused receiver asks for
/// nothing, and the end of the media told apart from a stop.
extension CastController {
    /// Polls in a row without an answer before the receiver is presumed gone (TV off, input
    /// switched, network moved: none of these announce themselves).
    private static let failureLimit = 8

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var failures = 0
            var ticks = 0
            var sawPlayback = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let transport = self.transport, !Task.isCancelled else { return }
                ticks += 1
                guard let state = await transport.status() else {
                    failures += 1
                    if failures >= Self.failureLimit {
                        await self.finish(reason: "receiver stopped answering", stopReceiver: false)
                        return
                    }
                    continue
                }
                failures = 0
                guard self.transport === transport else { return }
                self.apply(state)
                if state.phase == .playing || state.phase == .paused { sawPlayback = true }
                if state.phase == .finished || (sawPlayback && state.phase == .idle) {
                    // A DLNA renderer says only STOPPED: near the end it finished, else the TV stopped it.
                    let ended = state.phase == .finished || self.isNearEnd
                    await self.finish(reason: ended ? "media finished" : "receiver went idle", stopReceiver: false,
                                      ended: ended)
                    return
                }
                if ticks % 10 == 0 { self.reportProgress(ended: false) }
                if ticks % 20 == 0 { self.keepAlive() }
            }
        }
    }

    private func apply(_ state: CastPlaybackState) {
        guard var current = session?.state else { return }
        current.phase = state.phase
        current.position = state.position
        // A receiver that doesn't know the length (a transcode) keeps the one the server gave.
        if state.duration > 0 { current.duration = state.duration }
        if let volume = state.volume { current.volume = volume }
        session?.state = current
    }

    private var isNearEnd: Bool {
        guard let state = session?.state, state.duration > 0 else { return false }
        return state.position >= state.duration - 60 || state.position / state.duration >= 0.92
    }

    /// The `/history/progress` heartbeat the local player sends, for what plays on the TV.
    func reportProgress(ended: Bool) {
        guard let playback, let state = session?.state else { return }
        let duration = state.duration
        let position = ended ? max(state.position, duration) : state.position
        guard duration > 0, position > 0 else { return }
        let body = playback.request.progressReport(position: position, duration: duration,
                                                   paused: state.phase == .paused, ended: ended,
                                                   sourcePath: playback.path)
        Task { await APIClient.shared.reportProgress(body) }
    }

    /// The server reaps an HLS session that goes quiet for a minute, and a paused receiver
    /// fetches nothing.
    private func keepAlive() {
        guard let id = playback?.hlsSessionID else { return }
        let paused = session?.state.phase == .paused
        Task {
            _ = try? await APIClient.shared.sendRaw("POST", "/api/video/hls/\(APIClient.segment(id))/keepalive",
                                                    query: ["paused": String(paused)], promptOnLock: false, timeout: 10)
        }
    }

    /// Ends the cast: progress saved, the receiver stopped (when asked), the server session let go.
    func finish(reason: String, stopReceiver: Bool, ended: Bool = false) async {
        pollTask?.cancel()
        pollTask = nil
        // Nothing running: a failed attempt stays on the remote until it is dismissed.
        guard let transport else { return }
        log.notice("cast to \(transport.device.name) ended: \(reason)")
        reportProgress(ended: ended)
        self.transport = nil
        if stopReceiver { await transport.stop() }
        if let id = playback?.hlsSessionID { await APIClient.shared.stopLiveSession(id) }
        playback = nil
        session = nil
        CastPresenter.dismissRemote()
        PlaybackCoordinator.shared.playerDidClose()
        NotificationCenter.default.post(name: .continueWatchingChanged, object: nil)
    }
}
#endif
