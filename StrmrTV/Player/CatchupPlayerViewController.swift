import AetherEngine
import AVKit
import UIKit

/// Opens a past (or airing) guide programme from the provider's catch-up over whatever is on screen.
@MainActor
enum CatchupPlayback {
    static func play(_ channel: LiveChannel, program: EPGProgram) {
        let coordinator = PlaybackCoordinator.shared
        guard coordinator.resolving == nil, let engine = coordinator.sharedEngine else { return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top, !(top is EnginePlayerViewController) else { return }
        top.present(CatchupPlayerViewController(engine: engine, channel: channel, program: program), animated: true)
    }
}

/// A programme replayed from the provider's archive (catch-up), in the stock tvOS player over
/// AetherEngine, from its start, with no resume or watch state (as recordings play).
///
/// The server turns the programme into the provider's archive URL (`GET /api/live/catchup`), which
/// plays as a file through `/api/video/stream`: providers serve the archive whole, with a length
/// and byte ranges (an Xtream timeshift is one TS file for the programme), so AVKit's scrubber
/// seeks it like any VOD. A programme still airing replays up to the moment it was opened.
final class CatchupPlayerViewController: EnginePlayerViewController {
    let channel: LiveChannel
    let program: EPGProgram
    private var loadTask: Task<Void, Never>?
    private var didFinish = false
    private var lastPosition: Double = 0
    private lazy var cover = LiveLoadingCover(channel: channel, program: program)
    private lazy var softwareHUD = SoftwareTransportHUD(title: program.title, subtitle: channel.name)
    private static let seekStep: Double = 10
    private var scrubTarget: Double?
    private var scrubCommit: DispatchWorkItem?

    init(engine: AetherEngine, channel: LiveChannel, program: EPGProgram) {
        self.channel = channel
        self.program = program
        super.init(engine: engine, logCategory: "catchup-player")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.fill(cover, in: view)
        view.addSubview(cover)
        bindEngine()
        setInfoPanel(title: program.title, subtitle: channel.name, description: program.description)
        installStreamInfo(file: nil, source: StreamSource.joined([String(localized: "Catch-up"), channel.name]))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard loadTask == nil, !didFinish else { return }
        matchContent = view.window?.displayCriteriaMatchingEnabled ?? false
        open()
    }

    private func open() {
        log.notice("replaying \(channel.name): \(program.title) from \(program.start.ISO8601Format())")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let api = APIClient.shared
                let archive = try await api.liveCatchup(channel, program: program, offset: 0)
                try Task.checkCancellation()
                log.info("archive from \(archive.offsetSeconds)s for \(archive.durationSeconds)s")
                let url = api.catchupStreamURL(archive, channel: channel, program: program)
                _ = try await engine.load(url: url, startPosition: 0, options: baseLoadOptions())
                cover.isHidden = true
                log.info("opened, duration \(Int(engine.duration))s")
                engine.play()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                fail(error.localizedDescription)
            }
        }
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
                if time > 0 { lastPosition = time }
                guard softwareSurfaceMounted else { return }
                softwareHUD.update(position: scrubTarget ?? time, duration: engine.duration,
                                   paused: engine.state == .paused)
            }
            .store(in: &cancellables)
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .ended:
                    self?.log.notice("replay ended at \(Int(self?.lastPosition ?? 0))s")
                    self?.dismiss(animated: true)
                case let .error(message): self?.fail(message)
                default: break
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Software route (no AVPlayer, so no AVKit chrome)

    private func setSoftwareSurface(mounted: Bool) {
        guard mountSoftwareSurface(mounted) else { return }
        if mounted, softwareHUD.superview == nil {
            Self.fill(softwareHUD, in: view)
            view.addSubview(softwareHUD)
            softwareHUD.flash()
        } else if !mounted {
            softwareHUD.removeFromSuperview()
        }
    }

    override var softwareHUDHasOpenLayer: Bool { softwareSurfaceMounted && softwareHUD.isInfoShowing }

    override func closeSoftwareHUDLayer() {
        softwareHUD.setInfo(visible: false)
    }

    override func streamInfoDidChange(_ info: StreamInfo) {
        softwareHUD.setDetails(info.summary)
    }

    /// On the software route: Select / Play-Pause toggle, Left / Right seek 10 s, Down opens the
    /// Info card, Menu closes it or the player. Otherwise AVKit's own transport.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard softwareSurfaceMounted, let press = presses.first else { return super.pressesBegan(presses, with: event) }
        switch press.type {
        case .select, .playPause: engine.togglePlayPause()
        case .leftArrow: seek(by: -Self.seekStep)
        case .rightArrow: seek(by: Self.seekStep)
        case .downArrow: softwareHUD.setInfo(visible: !softwareHUD.isInfoShowing)
        case .upArrow: softwareHUD.setInfo(visible: false)
        case .menu:
            if !softwareHUD.isInfoShowing { dismiss(animated: true) }
            return
        default: return super.pressesBegan(presses, with: event)
        }
        softwareHUD.flash()
    }

    /// A run of presses is one seek, sent once the presses pause.
    private func seek(by delta: Double) {
        let target = min(max(0, (scrubTarget ?? lastPosition) + delta), max(0, engine.duration - 1))
        scrubTarget = target
        softwareHUD.update(position: target, duration: engine.duration, paused: engine.state == .paused)
        scrubCommit?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let target = scrubTarget else { return }
            Task {
                await self.engine.seek(to: target)
                self.scrubTarget = nil
            }
        }
        scrubCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: Lifecycle

    private func fail(_ message: String) {
        guard !didFinish else { return }
        log.error("catch-up playback failed: \(message)")
        PlaybackCoordinator.shared.errorMessage = message
        dismiss(animated: true)
    }

    override func finish() {
        guard !didFinish else { return }
        didFinish = true
        log.notice("player closed at \(Int(lastPosition))s")
        loadTask?.cancel()
        scrubCommit?.cancel()
        cancellables.removeAll()
        settingsHider.stop()
        player = nil
        setSoftwareSurface(mounted: false)
        engine.stop()
        PlaybackCoordinator.shared.playerDidClose()
    }
}
