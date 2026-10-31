import AetherEngine
import AVKit
import UIKit

/// Opens a live channel over whatever is on screen.
@MainActor
enum LivePlayback {
    static func play(_ channel: LiveChannel, program: EPGProgram?) {
        let coordinator = PlaybackCoordinator.shared
        guard coordinator.resolving == nil, let engine = coordinator.sharedEngine else { return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top, !(top is LivePlayerViewController) else { return }
        top.present(LivePlayerViewController(engine: engine, channel: channel, program: program), animated: true)
    }
}

/// A live channel in the stock tvOS player over AetherEngine. The server opens the channel
/// (`/api/live/hls/start`) as a direct stream, which the engine demuxes, or an HLS session,
/// which AVPlayer plays directly and which is kept alive every ten seconds and stopped on
/// close. When the engine gives up on the source (`liveSourceReset`, or an end of stream)
/// the channel is re-opened, at most three times, twenty seconds apart. A direct stream that
/// fails before its first frame is opened once more as HLS (`+HLSFallback`). Every tune uses
/// the fast live join, and a buffer that runs dry refills in place (`makeLoadOptions`).
///
/// Captions: see `LivePlayerViewController+Captions.swift`.
final class LivePlayerViewController: EnginePlayerViewController {
    let channel: LiveChannel
    let program: EPGProgram?
    private let api = APIClient.shared

    private var loadTask: Task<Void, Never>?
    var sessionID: String?
    /// The HLS session's playlist, which multiscreen takes over with the session (`addScreen`).
    private var playlistURL: URL?
    private var keepAliveTimer: Timer?
    var didFinish = false

    private var retuneCount = 0
    private var lastTune: Date?
    private static let retuneBudget = 3
    private static let retuneSpacing: TimeInterval = 20
    /// A retune that has played this long has recovered: the budget is restored, so it limits
    /// a channel that keeps failing, not one that drops out now and then over a long session.
    private static let retuneRecovery: TimeInterval = 120
    private var retuneRecoveryTimer: Timer?

    // The direct → HLS fallback (`+HLSFallback`).
    var hlsMode = HLSMode.asConfigured
    /// This tune is a direct stream, and has shown a frame.
    var tuneIsDirect = false
    var tunePlayed = false
    var hlsProofTimer: Timer?
    var hlsProofStalled = false
    /// The fallback came from an outright direct failure, not a deadline.
    var hlsFallbackRememberable = true
    /// A direct stream of this channel's source has played on this device (`LiveHLSPreference`).
    var directWorkedForSource = false
    var directStartTimer: Timer?

    private lazy var cover = LiveLoadingCover(channel: channel, program: program)
    private lazy var telemetry = LivePlaybackTelemetry(engine: engine, log: log)

    // Captions.
    var subtitleTracks: [TrackInfo] = []
    /// The selected track: an engine track id, `Self.serverCaptionsID`, or nil for off.
    var activeSubtitle: Int?
    /// The menu's last pick this session, re-applied after a retune when it is offered again.
    var pickedSubtitle: Int?
    var captionsWanted = LiveCaptionPreference.isOn
    var serverCaptions: ServerLiveCaptions?
    var serverCaptionClock: Timer?
    /// The menu entry for the server's captions; clear of every engine id.
    static let serverCaptionsID = -608

    init(engine: AetherEngine, channel: LiveChannel, program: EPGProgram?) {
        self.channel = channel
        self.program = program
        super.init(engine: engine, logCategory: "live")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Live: no seeking, and play / pause do nothing. AVKit's bar stays for its HUD.
        requiresLinearPlayback = true
        let swallow = UITapGestureRecognizer(target: nil, action: nil)
        swallow.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        // Presses only: with the default touch types it also took the touch-surface taps that
        // bring up AVKit's controls.
        swallow.allowedTouchTypes = []
        view.addGestureRecognizer(swallow)
        Self.fill(cover, in: view)
        view.addSubview(cover)
        bindEngine()
        telemetry.onDistress = { [weak self] in self?.noteHLSProofDistress($0) }
        telemetry.start()
        setInfoPanel(title: program?.title ?? channel.name, subtitle: program == nil ? nil : channel.name,
                     description: program?.description)
        installStreamInfo(file: nil, source: StreamSource.joined([String(localized: "Live TV"), channel.name]))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard loadTask == nil, !didFinish else { return }
        matchContent = view.window?.avDisplayManager.isDisplayCriteriaMatchingEnabled ?? false
        tune()
    }

    // MARK: Tuning

    /// `delay`: time for the old stream's provider connection to close first.
    func tune(after delay: TimeInterval = 0) {
        lastTune = Date()
        tuneIsDirect = false
        tunePlayed = false
        hlsProofTimer?.invalidate()
        directStartTimer?.invalidate()
        retuneRecoveryTimer?.invalidate()
        cover.isHidden = false
        // The new session starts with no subtitle; the pick is re-applied once it is offered.
        activeSubtitle = nil
        rebuildSubtitleMenu()
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                endSession()
                if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
                let forceHLS = await hlsForTune()
                let (url, sessionID) = try await api.startLive(channel, programTitle: program?.title, forceHLS: forceHLS)
                try Task.checkCancellation()
                self.sessionID = sessionID
                tuneIsDirect = sessionID == nil
                playlistURL = sessionID == nil ? nil : url
                startKeepAlive()
                startServerCaptions()
                log.notice("tuning \(self.channel.name) (\(sessionID == nil ? "direct" : "hls session"))")
                startDirectDeadline()
                _ = try await engine.load(url: url, options: makeLoadOptions(remoteHLS: sessionID != nil))
                engine.play()
            } catch is CancellationError {
                // A newer tune or the close replaced this one.
            } catch {
                guard !Task.isCancelled, !fallBackToHLS(error.localizedDescription) else { return }
                fail(error.localizedDescription)
            }
        }
    }

    /// Every tune joins with `.fastZap`, a few seconds behind the edge. A source that pauses and
    /// then bursts (an IPTV line holding back 3 to 5 s, then handing over several segments) can
    /// leave the playlist unchanged past AVPlayer's patience (-12888) or run the buffer dry; the
    /// player rides that out in place, as ExoPlayer does on Android TV, rather than retuning. A
    /// retune opened a new provider connection, dropped whatever was buffered and sat on black
    /// for the standard join's 18 s holdback, often just as the next burst arrived. Real
    /// failures (a source reset, the stream ending, an engine error) still retune or fail.
    private func makeLoadOptions(remoteHLS: Bool) -> LoadOptions {
        var options = baseLoadOptions()
        options.isLive = true
        options.liveJoinProfile = .fastZap
        // The server's HLS session goes straight to AVPlayer; a direct stream is demuxed.
        options.nativeRemoteHLS = remoteHLS
        if !remoteHLS {
            // The engine's 50 MiB probe is sized for VOD files with sparse tracks. A live TS read
            // arrives in real time: a 4K channel at ~15 Mbps spent 24 s of open_input reading
            // 45 MB of it and missed the 25 s first-frame deadline. 8 MiB is a few seconds of
            // such a channel, still the PMT and several keyframes.
            options.probesize = Self.liveDirectProbeBytes
            options.liveEdgeCushionSeconds = Self.liveDirectCushionSeconds
        }
        return options
    }

    private static let liveDirectProbeBytes: Int64 = 8 << 20

    /// Broadcast muxers (an HDHomeRun's ATSC feed) send each AC-3 frame up to ~0.8 s after the video
    /// of the same timestamp. At the bare edge the software clock starts on the first keyframe, so
    /// every audio frame reached the renderer already late: aLead sat at -0.2 to -0.8 s, the
    /// renderer never had enough data and the sound cut out a few seconds in while the picture
    /// played on. Joining 2 s back keeps the audio ~1.2 s ahead for ~1 s of extra tune time.
    private static let liveDirectCushionSeconds: Double = 2

    /// The source died under the engine: open the channel again, within the budget.
    private func retune(_ reason: String) {
        guard !didFinish, !fallBackToHLS(reason) else { return }
        let tooSoon = lastTune.map { Date().timeIntervalSince($0) < Self.retuneSpacing } ?? false
        guard retuneCount < Self.retuneBudget, !tooSoon else {
            log.error("retune exhausted after \(self.retuneCount) (\(reason))")
            fail(String(localized: "The channel keeps dropping out. Try it again in a moment."))
            return
        }
        retuneCount += 1
        log.notice("retune \(self.retuneCount): \(reason)")
        tune()
    }

    private func startRetuneRecovery() {
        retuneRecoveryTimer?.invalidate()
        guard retuneCount > 0 else { return }
        retuneRecoveryTimer = Timer.scheduledTimer(withTimeInterval: Self.retuneRecovery, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.didFinish, case .playing = self.engine.state else { return }
                self.log.info("retune budget restored after \(Int(Self.retuneRecovery)) s of playback")
                self.retuneCount = 0
            }
        }
    }

    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        guard sessionID != nil else { return }
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let id = self?.sessionID else { return }
                Task { await APIClient.shared.keepLiveSessionAlive(id) }
            }
        }
    }

    private func endSession() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        stopServerCaptions()
        playlistURL = nil
        guard let id = sessionID else { return }
        sessionID = nil
        Task { await APIClient.shared.stopLiveSession(id) }
    }

    // MARK: Engine binding

    private func bindEngine() {
        engine.$videoRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                self?.log.info("route \(route.rawValue)")
                self?.setSoftwareSurface(mounted: route == .software)
                if UserDefaults.standard.bool(forKey: "StrmrTmpNoControls"), route != .none { self?.showsPlaybackControls = false } // TMP-REPRO
            }
            .store(in: &cancellables)
        // The first frame, not `.playing`: the native path reports playing before the item is ready.
        engine.$hasFirstFrameReadyForDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                guard ready, let self else { return }
                log.info("first frame (route \(self.engine.videoRoute.rawValue))")
                cover.isHidden = true
                tunePlayed = true
                directStartTimer?.invalidate()
                startRetuneRecovery()
                noteDirectPlayed()
                startHLSProof()
            }
            .store(in: &cancellables)
        engine.$subtitleTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                guard let self else { return }
                if tracks.map(\.id) != subtitleTracks.map(\.id) {
                    log.info("subtitle tracks: " + tracks.map { "\($0.id) \($0.codec) \($0.language ?? "und")" }
                        .joined(separator: ", "))
                }
                subtitleTracks = tracks
                if let active = activeSubtitle, active != Self.serverCaptionsID,
                   !tracks.contains(where: { $0.id == active }) {
                    activeSubtitle = nil
                }
                applyCaptionPick()
                rebuildSubtitleMenu()
            }
            .store(in: &cancellables)
        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in
                guard let self, activeSubtitle != Self.serverCaptionsID else { return }
                subtitleOverlay.setCues(cues)
            }
            .store(in: &cancellables)
        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, activeSubtitle != Self.serverCaptionsID, subtitleOverlay.superview != nil else { return }
                subtitleOverlay.update(sourceTime: time)
            }
            .store(in: &cancellables)
        engine.liveSourceReset
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.retune("live source reset") }
            .store(in: &cancellables)
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                // Delivered a turn late: one the engine has already left (a failed direct
                // stream's error after the HLS fallback restarted it) is stale.
                guard let self, self.engine.state == state else { return }
                switch state {
                case .paused:
                    // Anything that still pauses a live channel (a remote command, AVKit) resumes it.
                    guard !self.didFinish, UIApplication.shared.applicationState == .active else { return }
                    self.engine.play()
                case .ended: self.retune("end of stream")
                case let .error(message):
                    guard !self.fallBackToHLS(message) else { return }
                    self.fail(message)
                default: break
                }
            }
            .store(in: &cancellables)
    }

    private func setSoftwareSurface(mounted: Bool) {
        guard mountSoftwareSurface(mounted) else { return }
        mountSubtitleOverlay()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Without AVKit's chrome (software route) Menu has to close the player itself.
        if softwareSurfaceMounted, presses.contains(where: { $0.type == .menu }) {
            dismiss(animated: true)
            return
        }
        // Nor is there a transport bar for the Subtitles menu: Select opens it instead.
        if softwareSurfaceMounted, presses.contains(where: { $0.type == .select }), !subtitleChoices.isEmpty {
            presentSubtitlePicker()
            return
        }
        if presses.contains(where: { $0.type == .playPause }) { return }
        super.pressesBegan(presses, with: event)
    }

    // MARK: Multiscreen

    /// The transport bar's Add Screen: this channel becomes multiscreen's first screen. An HLS
    /// session is handed over as it is (its keepalive stops here, but it is not stopped, and
    /// the teardown below no longer knows it); a direct stream ends and is opened again as HLS.
    func addScreen() {
        guard !didFinish else { return }
        let entry: MultiscreenEntry
        if let id = sessionID, let url = playlistURL {
            keepAliveTimer?.invalidate()
            keepAliveTimer = nil
            sessionID = nil
            playlistURL = nil
            entry = .session(channel, url: url, sessionID: id)
            log.notice("multiscreen: handing the hls session over")
        } else {
            entry = .tune(channel)
            log.notice("multiscreen: retuning as hls")
        }
        loadTask?.cancel()
        let presenter = presentingViewController
        dismiss(animated: true) {
            MultiscreenPresenter.open(entry, over: presenter)
        }
    }

    // MARK: Lifecycle

    private func fail(_ message: String) {
        guard !didFinish else { return }
        log.error("live playback failed: \(message)")
        PlaybackCoordinator.shared.errorMessage = message
        dismiss(animated: true)
    }

    override func finish() {
        guard !didFinish else { return }
        didFinish = true
        loadTask?.cancel()
        hlsProofTimer?.invalidate()
        directStartTimer?.invalidate()
        retuneRecoveryTimer?.invalidate()
        cancellables.removeAll()
        telemetry.stop()
        settingsHider.stop()
        player = nil
        setSoftwareSurface(mounted: false)
        engine.stop()
        endSession()
        PlaybackCoordinator.shared.playerDidClose()
    }
}
