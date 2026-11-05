import AetherEngine
import UIKit

/// The programme bar's state, held by the player (extensions have no stored properties).
@MainActor
final class LiveProgrammeScrub {
    let hud: SoftwareTransportHUD
    /// The point being picked with Left / Right, committed a moment after the last press.
    var target: Date?
    var commit: DispatchWorkItem?
    var lastPress = Date.distantPast
    var presses = 0
    var ticker: Timer?

    init(channel: LiveChannel) {
        hud = SoftwareTransportHUD(title: channel.name)
    }
}

/// A channel with provider catch-up shows the software route's transport (`SoftwareTransportHUD`,
/// laid out as AVKit's) on both routes instead of AVKit's own bar, which can only span what the
/// player holds: here the bar spans the programme at the playhead, shades what has aired, and
/// shows LIVE or how far behind. The remote works as on the software route: Left / Right pick a
/// point (its time of day above the bar; sent a moment after the last press, or with Select),
/// Play/Pause and Select pause when the tune can (a timeshift window, or the archive), Up focuses
/// the row (Start Over, Go Live, Add Screen, Subtitles), Down opens the Info card. Where a pick
/// lands is `LiveCatchupRules.decide`: in place inside the timeshift window or the archive
/// playing, else the archive there, or live.
extension LivePlayerViewController {
    var usesProgrammeBar: Bool { channel.catchupWindow != nil }
    private var hud: SoftwareTransportHUD { scrub.hud }

    func installProgrammeBar() {
        guard usesProgrammeBar else { return }
        showsPlaybackControls = false
        hud.onFocusChange = { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
        Self.fill(hud, in: view)
        view.insertSubview(hud, belowSubview: cover)
        scrub.ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshProgrammeBar() }
        }
    }

    func stopProgrammeBar() {
        scrub.ticker?.invalidate()
        scrub.commit?.cancel()
    }

    private var isPaused: Bool {
        if case .paused = engine.state { return true }
        return false
    }

    private var behindLive: TimeInterval { max(0, Date().timeIntervalSince(catchupPlayhead)) }

    func refreshProgrammeBar() {
        guard usesProgrammeBar else { return }
        let now = Date()
        let playhead = catchupPlayhead
        let at = scrub.target ?? playhead
        guard let program = LiveCatchupRules.program(at: at, in: catchupPrograms) else {
            hud.setTitle(channel.name, subtitle: nil)
            hud.update(position: 0, duration: 0, paused: isPaused)
            hud.setLive(airedFraction: nil, behind: max(0, now.timeIntervalSince(playhead)))
            return
        }
        let length = max(1, program.stop.timeIntervalSince(program.start))
        hud.setTitle(program.title, subtitle: channel.name)
        hud.update(position: at.timeIntervalSince(program.start), duration: length, paused: isPaused)
        hud.setLive(airedFraction: now.timeIntervalSince(program.start) / length,
                    behind: max(0, now.timeIntervalSince(playhead)))
    }

    /// The row: Start Over and Go Live, then AVKit's items (Add Screen, Subtitles).
    func refreshProgrammeRow() {
        guard usesProgrammeBar else { return }
        let startOver = UIAction(title: String(localized: "Start Over"), image: UIImage(systemName: "gobackward")) {
            [weak self] _ in self?.startOver()
        }
        let goLive = UIAction(title: String(localized: "Go Live"), image: UIImage(systemName: "forward.end")) {
            [weak self] _ in self?.programmeGoLive()
        }
        hud.setMenus([startOver, goLive] + transportBarCustomMenuItems)
    }

    // MARK: Remote

    /// The remote, while the bar is in use; true when the press was taken. With the row focused
    /// the focus engine moves along it and Select runs a button; only what leaves it lands here.
    func handleProgrammeBarPress(_ presses: Set<UIPress>) -> Bool {
        guard usesProgrammeBar, presentedViewController == nil, let press = presses.first?.type else { return false }
        switch press {
        case .playPause:
            if pausable { engine.togglePlayPause() }
        case .select:
            guard !hud.rowFocused, !hud.isActionFocused else { return true }
            if scrub.target != nil { commitScrub() } else if hud.isShowing, pausable { engine.togglePlayPause() }
        case .leftArrow, .rightArrow:
            guard !hud.rowFocused else { return true }
            if hud.isInfoShowing { hud.setInfo(visible: false) }
            step(forward: press == .rightArrow)
        case .upArrow:
            if hud.isInfoShowing {
                hud.setInfo(visible: false)
            } else if hud.isShowing, !hud.rowFocused {
                hud.focusRow()
            } else {
                hud.flash()
            }
            return true
        case .downArrow:
            if hud.rowFocused {
                hud.releaseRow()
                hud.flash()
            } else {
                hud.setInfo(visible: !hud.isInfoShowing)
            }
            return true
        case .menu:
            return softwareHUDHasOpenLayer
        default:
            return false
        }
        hud.flash()
        refreshProgrammeBar()
        return true
    }

    /// Menu closes what is open (a pick, the row, the Info card, then the bar) before the player.
    override var softwareHUDHasOpenLayer: Bool {
        usesProgrammeBar && presentedViewController == nil
            && (scrub.target != nil || hud.rowFocused || hud.isInfoShowing || hud.isShowing)
    }

    override func closeSoftwareHUDLayer() {
        if scrub.target != nil {
            cancelScrub()
        } else if hud.rowFocused || hud.isInfoShowing {
            hud.releaseRow()
            hud.setInfo(visible: false)
        } else {
            hud.hide()
        }
        refreshProgrammeBar()
    }

    /// The HUD takes focus for its row, as on the software route.
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        usesProgrammeBar && hud.wantsFocus ? [hud] : super.preferredFocusEnvironments
    }

    /// A menu closed from the row hands focus back to the player's container; take it back.
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        guard usesProgrammeBar, hud.wantsFocus, let next = context.nextFocusedView,
              next.isDescendant(of: view), !next.isDescendant(of: hud) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
    }

    // MARK: Picking a point

    /// 10 s a press, growing while the presses come quickly (as a held arrow).
    private func step(forward: Bool) {
        let now = Date()
        scrub.presses = now.timeIntervalSince(scrub.lastPress) < 0.6 ? scrub.presses + 1 : 0
        scrub.lastPress = now
        let size: TimeInterval = switch scrub.presses {
        case ..<4: 10
        case ..<10: 30
        default: 60
        }
        let earliest = now.addingTimeInterval(-(channel.catchupWindow ?? 0))
        let target = min(max((scrub.target ?? catchupPlayhead).addingTimeInterval(forward ? size : -size), earliest), now)
        scrub.target = target
        refreshProgrammeBar()
        if let program = LiveCatchupRules.program(at: target, in: catchupPrograms) {
            hud.showPreview(time: target.timeIntervalSince(program.start), duration: program.stop.timeIntervalSince(program.start),
                            image: nil, hasThumbnails: false, label: target.formatted(date: .omitted, time: .standard))
        }
        scrub.commit?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitScrub() }
        scrub.commit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func cancelScrub() {
        scrub.commit?.cancel()
        scrub.target = nil
        hud.hidePreview()
    }

    private func commitScrub() {
        guard let target = scrub.target else { return }
        cancelScrub()
        seekProgramme(to: target)
        refreshProgrammeBar()
    }

    /// What the player holds, as wall-clock dates: the archive playing, or the timeshift window.
    private var loadedSpan: ClosedRange<Date>? {
        if let archive = catchupArchive {
            let end = archive.start.addingTimeInterval(max(0, engine.duration - 5))
            return end > archive.start ? archive.start...end : nil
        }
        guard timeshifting, let range = engine.clock.seekableLiveRange else { return nil }
        let playhead = catchupPlayhead
        let position = engine.clock.currentTime
        let start = playhead.addingTimeInterval(range.lowerBound - position + 2)
        let end = playhead.addingTimeInterval(range.upperBound - position)
        return start < end ? start...end : nil
    }

    func seekProgramme(to date: Date) {
        guard let window = channel.catchupWindow else { return }
        let now = Date()
        switch LiveCatchupRules.decide(date, now: now, loaded: loadedSpan, programs: catchupPrograms, archiveWindow: window) {
        case .live:
            programmeGoLive()
        case let .inPlayer(target):
            let position = engine.clock.currentTime + target.timeIntervalSince(catchupPlayhead)
            log.info("programme bar: seek in place \(Int(now.timeIntervalSince(target)))s behind live")
            Task { await engine.seek(to: max(0, position)) }
        case let .archive(program, position):
            openCatchup(program, position: position)
        case .nothing:
            log.notice("programme bar: no archive \(Int(now.timeIntervalSince(date)))s behind live")
        }
    }

    func programmeGoLive() {
        if inCatchupArchive { return catchupGoLive() }
        guard timeshifting, behindLive > LiveTimeshiftStatusView.atLiveSeconds else { return }
        Task { await engine.seekToLiveEdge() }
    }
}
