import AetherEngine
import AVFoundation
import Combine
import Foundation

/// Field telemetry for a live channel, written to the app log so a submitted log shows how
/// playback went and not only how it started. On the HLS session route AVPlayer fetches the
/// segments from the server itself, and the server sees only that a request arrived, not how
/// long it took to deliver; AVPlayer's access log is the one place a stream that degrades
/// mid-session leaves evidence.
///
/// Every minute one `telemetry` line with the minute's deltas (the fetch rate while
/// transferring, media fetched against wall time, segments that arrived after their deadline,
/// stalls, dropped frames, error entries) and the state at the tick (distance behind the live
/// edge, forward buffer, why AVPlayer is waiting). Stalls and access errors are also logged as
/// they happen. The baseline is retaken whenever the engine hands over a new item (a retune).
@MainActor
final class LivePlaybackTelemetry {
    private let engine: AetherEngine
    private let log: AppLog
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var itemObservers: [NSObjectProtocol] = []
    private weak var item: AVPlayerItem?
    private var baseline: Totals?
    private var baselineAt = Date()
    private var attachedAt = Date()
    /// Access errors this minute; the first few are logged in full, the rest only counted.
    private var errorsThisWindow = 0

    private static let interval: TimeInterval = 60
    private static let errorLinesPerWindow = 5
    private static let readQueue = DispatchQueue(label: "com.strmr.app.nx.live-telemetry", qos: .utility)

    init(engine: AetherEngine, log: AppLog) {
        self.engine = engine
        self.log = log
    }

    func start() {
        engine.$currentAVPlayer
            .map { player -> AnyPublisher<AVPlayerItem?, Never> in
                guard let player else { return Just(nil).eraseToAnyPublisher() }
                return player.publisher(for: \.currentItem).eraseToAnyPublisher()
            }
            .switchToLatest()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in self?.attach(item) }
            .store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
        attach(nil)
    }

    // MARK: Item

    private func attach(_ newItem: AVPlayerItem?) {
        itemObservers.forEach(NotificationCenter.default.removeObserver)
        itemObservers = []
        item = newItem
        baseline = nil
        errorsThisWindow = 0
        guard let newItem else { return }
        attachedAt = Date()
        let center = NotificationCenter.default
        itemObservers.append(center.addObserver(forName: AVPlayerItem.playbackStalledNotification,
                                                object: newItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.logStall() }
        })
        itemObservers.append(center.addObserver(forName: AVPlayerItem.newErrorLogEntryNotification,
                                                object: newItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.logAccessError() }
        })
        Task { [weak self] in
            let reading = await Self.read(newItem)
            guard let self, self.item === newItem, self.baseline == nil else { return }
            self.baseline = reading.totals
            self.baselineAt = Date()
        }
    }

    private func logStall() {
        guard let item else { return }
        Task { [weak self] in
            let reading = await Self.read(item)
            guard let self, self.item === item else { return }
            self.log.notice("telemetry stall: behind \(Self.seconds(reading.behindLiveEdge)) "
                + "buf \(Self.seconds(reading.bufferAhead)) route \(self.engine.videoRoute.rawValue)")
        }
    }

    private func logAccessError() {
        guard let item else { return }
        errorsThisWindow += 1
        guard errorsThisWindow <= Self.errorLinesPerWindow else { return }
        Task { [weak self] in
            let event = await Self.lastErrorEvent(item)
            guard let self, self.item === item, let event else { return }
            self.log.error("telemetry access error: \(event)")
        }
    }

    // MARK: Tick

    private func tick() {
        guard let item, let player = engine.currentAVPlayer else { return }
        let status = Self.describe(player)
        Task { [weak self] in
            let reading = await Self.read(item)
            guard let self, self.item === item else { return }
            let now = Date()
            defer {
                self.baseline = reading.totals
                self.baselineAt = now
                self.errorsThisWindow = 0
            }
            guard let previous = self.baseline else { return }
            self.log.info(self.line(reading, since: previous, wall: now.timeIntervalSince(self.baselineAt),
                                    status: status))
        }
    }

    private func line(_ reading: Reading, since previous: Totals, wall: TimeInterval, status: String) -> String {
        let now = reading.totals
        let bytes = now.bytes - previous.bytes
        let transfer = now.transferDuration - previous.transferDuration
        let net = transfer > 0 ? Self.mbps(Double(bytes) * 8 / transfer) : "-"
        let media = now.segmentsDownloaded - previous.segmentsDownloaded
        let age = Int(Date().timeIntervalSince(attachedAt))
        return "telemetry route=\(engine.videoRoute.rawValue) t=\(age / 60)m\(age % 60)s"
            + " net=\(net) media=\(Int(media.rounded()))s/\(Int(wall.rounded()))s"
            + " req=+\(now.requests - previous.requests)"
            + " overdue=+\(now.overdue - previous.overdue)"
            + " stalls=+\(now.stalls - previous.stalls)(\(now.stalls))"
            + " dropped=+\(now.dropped - previous.dropped)"
            + " errors=+\(errorsThisWindow)"
            + " behind=\(Self.seconds(reading.behindLiveEdge)) buf=\(Self.seconds(reading.bufferAhead))"
            + " observed=\(now.observedBitrate.map(Self.mbps) ?? "-")"
            + " indicated=\(now.indicatedBitrate.map(Self.mbps) ?? "-")"
            + " entries=\(now.entries) status=\(status) rss=\(engine.liveTelemetry?.rssMb ?? 0)MB"
    }

    private static func describe(_ player: AVPlayer) -> String {
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

    // MARK: Reading

    /// The access log summed over its entries: AVFoundation opens a new entry when the playback
    /// session changes under it, and the newest alone would fall back mid-session.
    struct Totals {
        var entries = 0
        var stalls = 0
        var requests = 0
        var bytes: Int64 = 0
        var transferDuration: TimeInterval = 0
        var segmentsDownloaded: TimeInterval = 0
        var overdue = 0
        var dropped = 0
        var observedBitrate: Double?
        var indicatedBitrate: Double?
    }

    struct Reading {
        var totals = Totals()
        /// Seconds between the playhead and the end of the seekable range, i.e. the live edge.
        var behindLiveEdge: Double?
        /// Seconds loaded ahead of the playhead.
        var bufferAhead: Double?
    }

    /// The access log and time ranges are synchronous reads from the media server process;
    /// they are made off the main actor.
    private static func read(_ item: AVPlayerItem) async -> Reading {
        return await withCheckedContinuation { continuation in
            readQueue.async { continuation.resume(returning: readNow(item)) }
        }
    }

    private nonisolated static func readNow(_ item: AVPlayerItem) -> Reading {
        var reading = Reading()
        for event in item.accessLog()?.events ?? [] {
            reading.totals.entries += 1
            reading.totals.stalls += max(0, event.numberOfStalls)
            reading.totals.requests += max(0, event.numberOfMediaRequests)
            reading.totals.bytes += max(0, event.numberOfBytesTransferred)
            reading.totals.transferDuration += max(0, event.transferDuration)
            reading.totals.segmentsDownloaded += max(0, event.segmentsDownloadedDuration)
            reading.totals.overdue += max(0, event.downloadOverdue)
            reading.totals.dropped += max(0, event.numberOfDroppedVideoFrames)
            if event.observedBitrate > 0 { reading.totals.observedBitrate = event.observedBitrate }
            if event.indicatedBitrate > 0 { reading.totals.indicatedBitrate = event.indicatedBitrate }
        }
        let now = item.currentTime().seconds
        guard now.isFinite else { return reading }
        if let edge = item.seekableTimeRanges.last?.timeRangeValue.end.seconds, edge.isFinite {
            reading.behindLiveEdge = max(0, edge - now)
        }
        var ahead = 0.0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let end = range.end.seconds
            if end > now { ahead += end - max(range.start.seconds, now) }
        }
        reading.bufferAhead = ahead
        return reading
    }

    /// The newest error entry, without its URI: that carries the session's auth token.
    private static func lastErrorEvent(_ item: AVPlayerItem) async -> String? {
        return await withCheckedContinuation { continuation in
            readQueue.async {
                guard let event = item.errorLog()?.events.last else {
                    continuation.resume(returning: nil)
                    return
                }
                let file = event.uri.flatMap { URL(string: $0)?.lastPathComponent } ?? "-"
                continuation.resume(returning: "status \(event.errorStatusCode) \(event.errorDomain) "
                    + "\(event.errorComment ?? "") (\(file))")
            }
        }
    }
}
