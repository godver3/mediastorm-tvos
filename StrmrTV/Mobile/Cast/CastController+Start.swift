#if os(iOS)
import Foundation

/// Starting a cast, for a title (`start`) and a live channel (`startLive`) alike: what was
/// casting is replaced, the remote comes up at once, and the media is built and loaded on the
/// receiver, with a failure shown on the remote.
extension CastController {
    /// What a start has built for the receiver: its connection, the media to load, the server
    /// HLS session behind it (kept alive, stopped with the cast) and, for a title, what watch
    /// progress is reported against (nil for a live channel).
    struct Prepared {
        let transport: CastTransport
        let media: CastMedia
        let hlsSessionID: String?
        let playback: (request: PlaybackRequest, path: String)?
    }

    func begin(_ session: Session, prepare: @escaping @MainActor () async throws -> Prepared) async {
        startTask?.cancel()
        let device = session.device
        await finish(reason: "replaced by a new cast", stopReceiver: transport?.device.id != device.id)
        self.session = session
        CastPresenter.showRemote()
        let task = Task {
            // A server session built for this start that the cast hasn't taken over yet.
            var orphan: String?
            do {
                let prepared = try await prepare()
                orphan = prepared.hlsSessionID
                try Task.checkCancellation()
                hlsSessionID = prepared.hlsSessionID
                playback = prepared.playback
                transport = prepared.transport
                orphan = nil
                try await prepared.transport.load(prepared.media)
                try Task.checkCancellation()
                self.session?.phase = .active
                self.session?.canSeek = prepared.transport.canSeek && !prepared.media.isLive
                self.session?.state.duration = prepared.media.isLive ? 0 : prepared.media.duration ?? 0
                self.session?.state.position = prepared.media.startPosition
                startPolling()
            } catch is CancellationError {
                if let orphan { await APIClient.shared.stopLiveSession(orphan) }
            } catch {
                log.error("cast to \(device.name) failed: \(error.localizedDescription)")
                if let orphan { await APIClient.shared.stopLiveSession(orphan) }
                await transport?.stop()
                transport = nil
                if let id = hlsSessionID { await APIClient.shared.stopLiveSession(id) }
                hlsSessionID = nil
                playback = nil
                self.session?.phase = .failed(error.localizedDescription)
            }
        }
        startTask = task
        await task.value
    }
}
#endif
