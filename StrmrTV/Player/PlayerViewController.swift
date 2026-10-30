import AetherEngine
import AVKit
import UIKit

/// Stock tvOS player chrome (transport bar, info panel, audio/subtitle menus) over
/// AetherEngine, for a movie or episode. Split by concern: track menus (`+Tracks`), skip
/// segments and up next (`+UpNext`), software-route scrubbing (`+Scrub`), idle-connection
/// recovery with progress reporting (`+Recovery`) and online subtitles (`+OnlineSubtitles`).
/// State is internal for those files.
final class PlayerViewController: EnginePlayerViewController {
    let request: PlaybackRequest
    let url: URL
    let streamPath: String
    /// The server's track choice, or this device's (Settings › Playback overrides).
    var tracks: TrackPreferences
    /// The server admin's seek-preview switch (`playback.thumbnails.enabled`).
    let previewsEnabled: Bool

    lazy var softwareHUD = SoftwareTransportHUD(title: request.displayTitle, subtitle: request.displaySubtitle)
    private lazy var telemetry = VodPlaybackTelemetry(engine: engine, log: log)
    var progressTimer: Timer?
    var loadTask: Task<Void, Never>?
    var didFinish = false
    lazy var skipSegments = SkipSegments(request: request)
    lazy var thumbnails = PlaybackThumbnails(path: streamPath, request: request)
    var thumbnailsStarted = false
    /// Software route: where left / right presses have moved the seek to; committed once
    /// the presses pause, so a run of presses is one seek and the preview leads it.
    var scrubTarget: Double?
    var scrubCommit: DispatchWorkItem?
    var previewIndex: Int?
    static let scrubStep: Double = 10
    var activeSegment: SkipSegment?
    /// A segment whose button was dismissed with Menu; it isn't offered again.
    var dismissedSegment: SkipSegment?
    /// Speed picked from the Settings menu. The engine keeps it across same-source reloads
    /// (audio switches) and while paused.
    var playbackSpeed: Float = 1
    static let speedChoices: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    // Up next. The next episode's prequeue starts near the end; with the profile's credits
    // auto-skip on, the Next Episode button counts down and plays it by itself.
    lazy var nextEpisode = request.nextEpisode
    var creditsAutoSkip = false
    var didPrefetchNext = false
    var countdown: (remaining: Int, timer: Timer)?
    var isAdvancing = false
    static let countdownSeconds = 7
    /// Share of the runtime after which the next episode starts resolving (as the Expo player).
    static let prefetchFraction = 0.9

    /// Last position / duration seen while the session was healthy. Progress is reported from
    /// these, so a session the engine (or tvOS) has already torn down still saves where it was.
    var lastKnownPosition: Double = 0
    var lastKnownDuration: Double = 0

    // Idle-connection recovery (see `PlayerViewController+Recovery.swift`).
    var lifecycleObservers: [NSObjectProtocol] = []
    var isInBackground = false
    var wasBackgrounded = false
    var isExitingToDetails = false
    var pausedAt: Date?
    /// When the engine last swapped the AVPlayer item under a paused title (`observeItemSwaps`).
    var itemSwappedWhilePausedAt: Date?
    var resumeWatch: (position: Double, timer: Timer)?
    /// Pause length after which the source connection may have gone idle and died.
    static let idleSocketPause: TimeInterval = 30
    /// How long a resume after such a pause may go without progress before giving up.
    static let resumeProgressWindow: TimeInterval = 20
    /// How soon after an item swap under a pause a resume is taken as the engine's, not the viewer's.
    static let swapResumeWindow: TimeInterval = 3

    // Subtitle menu state. `userPickedSubtitle` keeps a menu choice across reloads.
    var subtitleTracks: [TrackInfo] = []
    var activeSubtitle: Int?
    var userPickedSubtitle = false

    // Online subtitles (auto search, Search Online…, translation); see `+OnlineSubtitles`.
    lazy var onlineSubtitles = OnlineSubtitles(query: subtitleQuery, streamPath: streamPath)
    let subtitleStatus = SubtitleStatusToast()
    /// The Search Online… or Translate… page while it is up, and whether closing it resumes playback.
    var subtitleSearch: (page: UIViewController, resume: Bool)?

    // Switch Source (see `+SwitchSource`): what is playing, the languages carried onto it, and
    // the ranked sources once searched.
    var currentSource = SourceSwitch.Current()
    var trackCarry: TrackCarry?
    var sourceList: SourceSwitchList?

    // Audio menu state.
    var audioTracks: [TrackInfo] = []
    var pendingAudioPick: Int?
    var audioPickTask: Task<Void, Never>?

    init(engine: AetherEngine, request: PlaybackRequest, url: URL, streamPath: String,
         tracks: TrackPreferences, previewsEnabled: Bool) {
        self.request = request
        self.url = url
        self.streamPath = streamPath
        self.tracks = tracks
        self.previewsEnabled = previewsEnabled
        super.init(engine: engine, logCategory: "player")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        bindEngine()
        bindOnlineSubtitles()
        observeAppLifecycle()
        observeItemSwaps()
        setInfoPanel(title: request.displayTitle, subtitle: request.displaySubtitle,
                     description: request.infoDescription, artworkURL: request.infoArtworkURL)
        installStreamInfo(file: currentSource.releaseName, source: currentSource.origin)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard loadTask == nil else { return }
        if nextEpisode != nil {
            Task { [weak self] in
                let enabled = await PlaybackCoordinator.shared.creditsAutoSkipEnabled()
                self?.creditsAutoSkip = enabled
            }
        }
        matchContent = view.window?.avDisplayManager.isDisplayCriteriaMatchingEnabled ?? false
        telemetry.start()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                await TrackSettingsStore.shared.loadIfNeeded()
                _ = try await engine.load(
                    url: url,
                    startPosition: request.startPosition,
                    options: makeLoadOptions(),
                    audioSourceStreamIndex: tracks.audioStreamIndex.map(Int32.init)
                )
                applyDeviceTrackOverrides()
                if !applyTrackCarry() { applyServerAudioPick() }
                if case let .percent(percent) = request.start, engine.duration > 0 {
                    // Percentage-only resume (e.g. a Trakt import): now the duration is known.
                    await engine.seek(to: engine.duration * percent / 100)
                }
                engine.play()
                startProgressTimer()
                await applySubtitlePick()
                startAutoSubtitleSearch()
            } catch is CancellationError {
                return
            } catch {
                fail("Playback failed: \(error.localizedDescription)")
            }
        }
    }

    func makeLoadOptions() -> LoadOptions {
        var options = baseLoadOptions()
        // Scrub thumbnails on the hardware route: an I-frame rendition in the engine's master
        // is the one input AVPlayerViewController takes previews from (the backend's JPEGs
        // have no public way in). The engine leaves it out where it can't serve every
        // keyframe (MPEG-TS, single-connection origins, …) and logs why.
        options.serveIFramePlaylist = previewsEnabled
        // TrueHD Atmos / DTS:X heights (Settings › Playback); the engine renders them on VOD only.
        options.objectAudioRendering = AtmosSettingsStore.shared.rendering
        return options
    }

    // MARK: Engine binding

    private func bindEngine() {
        engine.$videoRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in self?.setSoftwareSurface(mounted: route == .software) }
            .store(in: &cancellables)

        engine.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self else { return }
                noteProgress(time)
                updateSkipAction(at: time)
                prefetchNextIfNear(time)
                guard softwareSurfaceMounted else { return }
                softwareHUD.update(position: scrubTarget ?? time, duration: engine.duration,
                                   paused: engine.state == .paused)
            }
            .store(in: &cancellables)

        // Both routes: the overlay draws the engine's cues against the frame on screen.
        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in
                // The online track's cues are the app's own; the engine has none selected then.
                guard let self, activeSubtitle != OnlineSubtitles.trackID else { return }
                subtitleOverlay.setCues(cues)
            }
            .store(in: &cancellables)
        // The device's subtitle style (Settings, or the subtitle menu's Style picks), live.
        SubtitleStyleStore.shared.$style
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in
                guard let self else { return }
                subtitleOverlay.style = style
                if !subtitleTracks.isEmpty { rebuildTrackMenus() }
            }
            .store(in: &cancellables)
        engine.clock.$sourceTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, subtitleOverlay.superview != nil else { return }
                subtitleOverlay.update(sourceTime: time)
            }
            .store(in: &cancellables)

        // Audio: the engine serves only the active track to AVPlayer, so AVKit's own audio
        // list has one entry. A transport-bar menu lists every track in the source.
        engine.$audioTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                self?.audioTracks = tracks
                self?.rebuildTrackMenus()
            }
            .store(in: &cancellables)
        engine.$subtitleTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                self?.subtitleTracks = tracks
                self?.rebuildTrackMenus()
            }
            .store(in: &cancellables)
        engine.$activeAudioTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                if let pending = pendingAudioPick, pending == active {
                    log.info("audio switch to stream \(pending) confirmed")
                    pendingAudioPick = nil
                    audioPickTask?.cancel()
                }
                rebuildTrackMenus(active: active)
            }
            .store(in: &cancellables)

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handleStateChange(state) }
            .store(in: &cancellables)
    }

    /// The software route also gets its own HUD (and scrub previews) and the subtitle overlay
    /// above its surface; the native route's overlay goes back in AVKit's content overlay.
    private func setSoftwareSurface(mounted: Bool) {
        guard mountSoftwareSurface(mounted) else { return }
        if mounted {
            softwareHUD.onFocusChange = { [weak self] in
                self?.setNeedsFocusUpdate()
                self?.updateFocusIfNeeded()
            }
            Self.fill(softwareHUD, in: view)
            Self.fill(subtitleOverlay, in: overlayHost)
            overlayHost.insertSubview(subtitleOverlay, aboveSubview: softwareSurface)
            view.addSubview(softwareHUD)
            softwareHUD.flash()
            startThumbnails()
        } else {
            subtitleOverlay.removeFromSuperview()
            softwareHUD.removeFromSuperview()
            if !didFinish { mountSubtitleOverlay() }
        }
    }

    /// The engine loaded the server's audio pick by container stream index; confirm it against
    /// the engine's track list (typeIndex, then language + languageIndex) and switch if needed.
    private func applyServerAudioPick() {
        guard let id = tracks.audioTrackID(in: engine.audioTracks), id != engine.activeAudioTrackIndex else { return }
        log.info("server audio pick: switching to stream \(id)")
        engine.selectAudioTrack(index: id)
    }

    /// The software route's HUD takes focus for its menu row and Skip capsule.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        softwareSurfaceMounted && softwareHUD.wantsFocus ? [softwareHUD] : super.preferredFocusEnvironments
    }

    /// A menu closed from the HUD's row hands focus to AVKit's container rather than back to the
    /// button it opened from; while the HUD wants focus, take it back, as AVKit's own bar does.
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard softwareSurfaceMounted, softwareHUD.wantsFocus, let next = context.nextFocusedView,
              next.isDescendant(of: view), !next.isDescendant(of: softwareHUD) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Presses a page over the player (the subtitle search, Switch Source) leaves unhandled come
        // back up the responder chain; they are not the player's (Menu would close it, arrows seek).
        guard subtitleSearch == nil, presentedViewController == nil else { return }
        guard softwareSurfaceMounted, let press = presses.first else {
            dismissSkipActionIfMenu(presses)
            return super.pressesBegan(presses, with: event)
        }
        if !handleSoftwarePress(press) { super.pressesBegan(presses, with: event) }
    }

    override func infoArtworkDidLoad(_ image: UIImage) {
        softwareHUD.setArtwork(image)
    }

    override func streamInfoDidChange(_ info: StreamInfo) {
        softwareHUD.setDetails(info.summary)
    }

    // MARK: Lifecycle

    func fail(_ message: String) {
        guard !didFinish, !isExitingToDetails else { return }
        log.error("playback failed: \(message)")
        PlaybackCoordinator.shared.errorMessage = message
        dismiss(animated: true)
    }

    private func handleStateChange(_ state: PlaybackState) {
        // While backgrounded the engine's own suspension policy may tear the item down;
        // nothing it reports then is the user's playback (we leave on return anyway).
        guard !isInBackground, !didFinish, !isExitingToDetails else { return }
        switch state {
        case .paused:
            if pausedAt == nil { pausedAt = Date() }
        case .playing:
            if let swappedAt = itemSwappedWhilePausedAt,
               Date().timeIntervalSince(swappedAt) < Self.swapResumeWindow {
                // The engine's reload resumed it, not the viewer; `pausedAt` stays as it was.
                log.notice("engine reload resumed a paused title at \(self.lastKnownPosition)s; keeping it paused")
                engine.pause()
                return
            }
            if let pausedAt, Date().timeIntervalSince(pausedAt) >= Self.idleSocketPause {
                armResumeWatch()
            }
            pausedAt = nil
        case .ended:
            // A long pause can leave the source connection dead; its read then surfaces as
            // end-of-file. A real end lands in the last couple of minutes.
            if resumeWatch != nil || (lastKnownDuration > 0 && lastKnownPosition < lastKnownDuration - 120) {
                exitToDetails(reason: "end of stream at \(Int(lastKnownPosition))s of \(Int(lastKnownDuration))s")
                return
            }
            reportProgress(ended: true)
            if let nextEpisode {
                playNext(nextEpisode)
            } else {
                dismiss(animated: true)
            }
        case let .error(message):
            if resumeWatch != nil {
                exitToDetails(reason: "error after resume: \(message)")
            } else {
                fail(message)
            }
        default:
            break
        }
    }

    override func finish() {
        guard !didFinish else { return }
        didFinish = true
        log.notice("player closed at \(self.lastKnownPosition)s of \(self.lastKnownDuration)s")
        loadTask?.cancel()
        audioPickTask?.cancel()
        progressTimer?.invalidate()
        telemetry.stop()
        disarmResumeWatch()
        stopCountdown()
        settingsHider.stop()
        skipSegments.cancel()
        scrubCommit?.cancel()
        thumbnails.cancel()
        onlineSubtitles.cancel()
        sourceList?.cancel()
        subtitleStatus.hide()
        reportProgress(ended: true, paused: isExitingToDetails)
        cancellables.removeAll()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers = []
        player = nil
        setSoftwareSurface(mounted: false)
        engine.stop()
        PlaybackCoordinator.shared.playerDidClose()
    }
}
