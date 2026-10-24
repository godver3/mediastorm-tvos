import AetherEngine
import Combine
import Foundation

/// What a tile reports about its stream, for the overlay.
struct MultiscreenStreamInfo: Equatable {
    var width = 0
    var height = 0
    var frameRate: Double?
    var audioCodec: String?

    /// "1080p · 50 fps · AAC", from whatever is known.
    var label: String? {
        var parts: [String] = []
        if height > 0 { parts.append(height >= 2000 ? "4K" : "\(height)p") }
        if let frameRate, frameRate > 0 {
            parts.append(String(localized: "\(frameRate.formatted(.number.precision(.fractionLength(0...2)))) fps"))
        }
        if let audioCodec, !audioCodec.isEmpty { parts.append(audioCodec.uppercased()) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One screen's player: its own AetherEngine (never the full-screen player's shared one),
/// loaded as a `.secondary` output so a tile never switches the display's mode or claims Now
/// Playing, and the ten-second keepalive of the session it plays. Stopping that session is
/// the `MultiscreenSession`'s job. No retune: when the engine gives up, `onFailure` reports it.
@MainActor
final class MultiscreenTilePlayer: ObservableObject {
    private(set) var engine: AetherEngine?
    @Published private(set) var info: MultiscreenStreamInfo?
    @Published private(set) var hasPicture = false

    /// The source given up on, when it is still the one playing.
    var onFailure: ((MultiscreenSource) -> Void)?

    private(set) var source: MultiscreenSource?
    private var audible = false
    private var active = true
    private var loadTask: Task<Void, Never>?
    private var keepAliveTimer: Timer?
    private var infoTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let log = AppLog(category: "multiscreen")

    /// Plays `source`, or stops when it is nil. The same source again changes nothing.
    func play(_ source: MultiscreenSource?) {
        guard source != self.source else { return }
        stopPlayback()
        self.source = source
        guard let source, let engine = engineForUse() else { return }
        startKeepAlive(source.sessionID)
        loadTask = Task { [weak self] in
            do {
                _ = try await engine.load(url: source.url, options: Self.loadOptions())
                guard let self, !Task.isCancelled, self.source == source else { return }
                if self.active { engine.play() }
            } catch {
                guard let self, !Task.isCancelled, self.source == source else { return }
                self.log.error("tile load failed: \(error.localizedDescription)")
                self.onFailure?(source)
            }
        }
        infoTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readInfo() }
        }
    }

    /// Full volume for the screen being listened to; silence for the others.
    func setAudible(_ audible: Bool) {
        self.audible = audible
        engine?.volume = audible ? 1 : 0
    }

    /// Paused while the app is in the background or the slot is not playing.
    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        guard source != nil, let engine else { return }
        if active { engine.play() } else { engine.pause() }
    }

    /// Stops playback for good (multiscreen closed).
    func shutdown() {
        stopPlayback()
        source = nil
        cancellables.removeAll()
        engine = nil
    }

    // MARK: Plumbing

    /// Live HLS straight to AVPlayer, joined fast, with no display matching.
    private static func loadOptions() -> LoadOptions {
        var options = LoadOptions()
        options.httpHeaders = APIClient.shared.mediaHeaders
        options.matchContentEnabled = false
        options.preferredAudioLanguages = TrackPreferences.deviceLanguages
        options.prepareNativeSubtitles = false
        options.isLive = true
        options.liveJoinProfile = .fastZap
        options.nativeRemoteHLS = true
        options.sharedOutputRole = .secondary
        return options
    }

    private func engineForUse() -> AetherEngine? {
        if let engine { return engine }
        do {
            let engine = try AetherEngine()
            engine.deactivatesAudioSessionOnStop = true
            // A muted tile's audio still decodes: on the remote-HLS route AVPlayer owns the
            // audio selection, so there is no track to turn off. Silence is the most it gets.
            engine.volume = audible ? 1 : 0
            self.engine = engine
            bind(engine)
            return engine
        } catch {
            log.error("tile engine failed to start: \(error.localizedDescription)")
            return nil
        }
    }

    private func bind(_ engine: AetherEngine) {
        engine.$hasFirstFrameReadyForDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in self?.hasPicture = ready }
            .store(in: &cancellables)
        engine.liveSourceReset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.gaveUp("live source reset") }
            .store(in: &cancellables)
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self, source != nil else { return }
                switch state {
                case .paused:
                    // Live doesn't pause: anything that paused it (AVKit, a remote command) is undone.
                    if active { engine.play() }
                case .ended: gaveUp("end of stream")
                case let .error(message): gaveUp(message)
                default: break
                }
            }
            .store(in: &cancellables)
    }

    private func gaveUp(_ reason: String) {
        guard let source else { return }
        log.notice("tile stream ended: \(reason)")
        onFailure?(source)
    }

    private func stopPlayback() {
        loadTask?.cancel()
        loadTask = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        infoTimer?.invalidate()
        infoTimer = nil
        info = nil
        if source != nil { engine?.stop() }
    }

    private func startKeepAlive(_ sessionID: String?) {
        guard let sessionID else { return }
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { await APIClient.shared.keepLiveSessionAlive(sessionID) }
        }
    }

    private func readInfo() {
        guard let engine else { return }
        var next = MultiscreenStreamInfo()
        next.width = Int(engine.sourceVideoWidth)
        next.height = Int(engine.sourceVideoHeight)
        if next.height == 0, let size = engine.currentAVPlayerItem?.presentationSize, size.height > 0 {
            next.width = Int(size.width)
            next.height = Int(size.height)
        }
        next.frameRate = engine.sourceVideoFrameRate
        let audio = engine.audioTracks
        next.audioCodec = (audio.first { $0.id == engine.activeAudioTrackIndex } ?? audio.first)?.codec
        let value = next == MultiscreenStreamInfo() ? nil : next
        if value != info { info = value }
    }
}
