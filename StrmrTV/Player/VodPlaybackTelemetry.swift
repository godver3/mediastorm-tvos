import AetherEngine
import AVFoundation
import Combine
import Foundation

/// Field telemetry for a movie or episode, written to the app log so a submitted log shows how
/// playback went and not only how it started. The server sees the byte ranges the engine asks
/// for, never whether the picture kept moving; a report of "lots of buffering" left nothing on
/// this side to tell a slow source from a stall with data already in hand.
///
/// Each rebuffer is logged as it starts (where the playhead was, what was buffered, what the
/// link was doing) and as it ends (how long it took). Every minute one `telemetry` line with the
/// minute's deltas (media played against wall time, time paused and rebuffering, bytes pulled
/// from the source, dropped frames) and the engine's readings at the tick. The engine refreshes
/// those readings once a second on both routes (`AetherEngine.liveTelemetry`), live or not.
@MainActor
final class VodPlaybackTelemetry {
    private let engine: AetherEngine
    private let log: AppLog
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var startedAt = Date()
    private var window = Window()
    private var stallStart: (at: Date, position: Double)?
    private var pausedSince: Date?
    private var stallCount = 0
    private var stallSeconds: TimeInterval = 0
    private var loggedFormat = false

    private static let interval: TimeInterval = 60

    /// What the minute's line differences against, retaken at every tick.
    private struct Window {
        var at = Date()
        var position: Double?
        var sourceBytes: Int64?
        var dropped: Int?
        var stalls = 0
        var stallSeconds: TimeInterval = 0
        var pausedSeconds: TimeInterval = 0
    }

    init(engine: AetherEngine, log: AppLog) {
        self.engine = engine
        self.log = log
    }

    func start() {
        startedAt = Date()
        engine.$isBuffering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffering in self?.bufferingChanged(buffering) }
            .store(in: &cancellables)
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.stateChanged(state) }
            .store(in: &cancellables)
        engine.$hasFirstFrameReadyForDisplay
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.logFormat() }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        guard timer != nil else { return }
        if stallStart != nil { bufferingChanged(false) }
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        let age = Int(Date().timeIntervalSince(startedAt))
        log.info("telemetry summary t=\(age / 60)m\(age % 60)s stalls=\(stallCount) "
            + "stalled=\(Self.seconds(stallSeconds)) route=\(engine.videoRoute.rawValue)")
    }

    // MARK: Events

    /// Once per session, at the first frame: what is being played and how, so the minute lines
    /// below have a bitrate and a decode path to be read against.
    private func logFormat() {
        guard !loggedFormat else { return }
        loggedFormat = true
        // The first minute's line then covers playback from its first frame, not from the next tick.
        let telemetry = engine.liveTelemetry
        window = Window(position: engine.currentTime, sourceBytes: telemetry?.demuxerBytesFetched,
                        dropped: telemetry?.droppedFrameCount)
        let size = engine.sourceVideoBitrate > 0 ? Self.mbps(Double(engine.sourceVideoBitrate)) : "-"
        log.info("telemetry format route=\(engine.videoRoute.rawValue) backend=\(engine.playbackBackend)"
            + " codec=\(engine.sourceVideoCodecName ?? "-") container=\(engine.sourceContainerFormat ?? "-")"
            + " video=\(engine.sourceVideoFormat) dv=\(engine.sourceDVProfile.map(String.init) ?? "-")"
            + " fps=\(engine.sourceVideoFrameRate.map { String(format: "%.3f", $0) } ?? "-")"
            + " bitrate=\(size) audio=\(engine.audioDelivery)"
            + " decoders=\(engine.activeVideoDecoder ?? "-")/\(engine.activeAudioDecoder ?? "-")")
    }

    private func bufferingChanged(_ buffering: Bool) {
        let now = Date()
        if buffering {
            guard stallStart == nil else { return }
            stallStart = (now, engine.currentTime)
            stallCount += 1
            window.stalls += 1
            log.notice("telemetry stall at \(Self.seconds(engine.currentTime)) \(readings())")
        } else if let start = stallStart {
            stallStart = nil
            let length = now.timeIntervalSince(start.at)
            stallSeconds += length
            window.stallSeconds += length
            log.notice("telemetry stall ended after \(Self.seconds(length)) "
                + "(at \(Self.seconds(start.position)), \(stallCount) this session) \(readings())")
        }
    }

    private func stateChanged(_ state: PlaybackState) {
        let now = Date()
        if state == .paused {
            if pausedSince == nil { pausedSince = now }
        } else if let since = pausedSince {
            window.pausedSeconds += now.timeIntervalSince(since)
            pausedSince = nil
        }
    }

    // MARK: Tick

    private func tick() {
        let now = Date()
        let telemetry = engine.liveTelemetry
        let position = engine.currentTime
        var paused = window.pausedSeconds
        if let since = pausedSince {
            paused += now.timeIntervalSince(since)
            pausedSince = now
        }
        var stalled = window.stallSeconds
        if let start = stallStart {
            // A stall still running counts toward the minute it spans; the rest goes to the next.
            stalled += now.timeIntervalSince(max(start.at, window.at))
        }
        defer {
            window = Window(at: now, position: position, sourceBytes: telemetry?.demuxerBytesFetched,
                            dropped: telemetry?.droppedFrameCount)
        }
        guard let previous = window.position else { return }
        let wall = now.timeIntervalSince(window.at)
        let played = position - previous
        var source = "-"
        if let bytes = telemetry?.demuxerBytesFetched, let before = window.sourceBytes, wall > 0 {
            source = Self.mbps(Double(bytes - before) * 8 / wall)
        }
        var dropped = "-"
        if let frames = telemetry?.droppedFrameCount, let before = window.dropped {
            dropped = "+\(frames - before)"
        }
        let age = Int(now.timeIntervalSince(startedAt))
        log.info("telemetry t=\(age / 60)m\(age % 60)s pos=\(Self.seconds(position))"
            + " played=\(Self.seconds(played))/\(Self.seconds(wall)) paused=\(Self.seconds(paused))"
            + " stalls=+\(window.stalls)(\(stallCount)) stalled=\(Self.seconds(stalled))"
            + " source=\(source) dropped=\(dropped) \(readings())")
    }

    /// The engine's readings right now: the AVPlayer side's forward buffer and the decoded cushion,
    /// the reader's runway ahead of the demuxer, the link rate while it delivers, the media rate
    /// played, and why AVPlayer is waiting when it is.
    private func readings() -> String {
        let telemetry = engine.liveTelemetry
        let window = telemetry?.readerWindowAheadBytes.map { String(format: "%.1fMB", Double($0) / 1_048_576) }
        return "route=\(engine.videoRoute.rawValue)"
            + " buf=\(Self.seconds(telemetry?.forwardBufferSeconds))"
            + " cushion=\(Self.seconds(telemetry?.displayCushionSeconds))"
            + " ahead=\(window ?? "-")"
            + " net=\(telemetry?.networkThroughputMbps.map { String(format: "%.1fMbps", $0) } ?? "-")"
            + " rate=\(telemetry?.instantBitrateMbps.map { String(format: "%.1fMbps", $0) } ?? "-")"
            + " avg=\(telemetry?.averageBitrateMbps.map { String(format: "%.1fMbps", $0) } ?? "-")"
            + " restarts=\(telemetry?.producerRestartCount ?? 0)"
            + " status=\(status()) rss=\(telemetry?.rssMb ?? 0)MB"
    }

    private func status() -> String {
        guard let player = engine.currentAVPlayer else { return "\(engine.state)" }
        switch player.timeControlStatus {
        case .playing: return "playing"
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate:
            switch player.reasonForWaitingToPlay {
            case .toMinimizeStalls?: return "waiting(stalls)"
            case .evaluatingBufferingRate?: return "waiting(buffering-rate)"
            case .noItemToPlay?: return "waiting(no-item)"
            case let reason?: return "waiting(\(reason.rawValue))"
            case nil: return "waiting"
            }
        @unknown default: return "unknown"
        }
    }

    private static func mbps(_ bitsPerSecond: Double) -> String {
        String(format: "%.1fMbps", bitsPerSecond / 1_000_000)
    }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.1fs", $0) } ?? "-"
    }
}
