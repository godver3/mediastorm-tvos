import AetherEngine
import AVKit
import UIKit

/// The provider's archive playing in place of the channel.
struct LiveCatchupArchive {
    let program: EPGProgram
    /// The wall-clock time at the file's start (the provider may round it down a little).
    let start: Date
    /// Where playback started in the file.
    let firstPosition: TimeInterval
}

/// Rewind into the provider's catch-up from a live channel that has it. Rewinding past what the
/// player holds (the start of the engine's timeshift window, or anything on a tune without one)
/// plays the provider's archive of the programme at that point instead; Start Over plays it from
/// the programme's start. The archive is always asked for from the programme's start, so AVKit's
/// bar spans the programme up to what had aired, and playback starts at the point wanted. The
/// channel's session is stopped meanwhile (a provider may allow one connection). An archive runs
/// up to when it was asked for, so at its end a fresh one carries on from there, into the next
/// programme when this one has ended; Go Live (or catching up with the edge) tunes the channel.
extension LivePlayerViewController {
    var inCatchupArchive: Bool { catchupArchive != nil }

    func hideCover() {
        cover.isHidden = true
        cover.show(note: nil)
    }

    /// The playhead as a wall-clock date: the archive's point, or now less how far behind live.
    var catchupPlayhead: Date {
        if let archive = catchupArchive { return archive.start.addingTimeInterval(engine.clock.currentTime) }
        return Date().addingTimeInterval(-(timeshifting ? engine.clock.behindLiveSeconds : 0))
    }

    /// Loads the channel's guide around now, and again every 15 minutes, for the programmes an
    /// archive is asked for by.
    func startCatchupSchedule() {
        guard let window = channel.catchupWindow else { return }
        delegate = self
        catchupScheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadCatchupSchedule(window: window)
                try? await Task.sleep(for: .seconds(15 * 60))
            }
        }
    }

    private func loadCatchupSchedule(window: TimeInterval) async {
        let back = Int(min(window, 12 * 3600) / 60)
        do {
            let programs = try await api.epgSchedule([channel.guideKey], startOffsetMinutes: -back, hours: back / 60 + 4)
            catchupPrograms = (programs[channel.guideKey] ?? []).filter { $0.stop > $0.start }.sorted { $0.start < $1.start }
            log.info("catch-up: \(self.catchupPrograms.count) programmes in the guide")
            rebuildSubtitleMenu()
        } catch {
            log.error("catch-up: schedule failed: \(error.localizedDescription)")
        }
    }

    /// The transport bar's Start Over and Go Live.
    func catchupMenuItems() -> [UIMenuElement] {
        guard channel.catchupWindow != nil, !catchupPrograms.isEmpty else { return [] }
        var items: [UIMenuElement] = [
            UIAction(title: String(localized: "Start Over"), image: UIImage(systemName: "gobackward")) { [weak self] _ in
                self?.startOver()
            },
        ]
        if inCatchupArchive {
            items.append(UIAction(title: String(localized: "Go Live"), image: UIImage(systemName: "forward.end")) { [weak self] _ in
                self?.catchupGoLive()
            })
        }
        return items
    }

    /// The programme at the playhead from its start.
    func startOver() {
        guard let program = LiveCatchupRules.program(at: catchupPlayhead, in: catchupPrograms), channel.canReplay(program) else {
            log.notice("catch-up: nothing to start over")
            return
        }
        openCatchup(program, position: 0)
    }

    /// A rewind to `date`: the archive there, live when it is now, else nothing.
    @discardableResult
    func rewindIntoCatchup(to date: Date) -> Bool {
        guard let window = channel.catchupWindow else { return false }
        switch LiveCatchupRules.seek(to: date, now: Date(), programs: catchupPrograms, archiveWindow: window) {
        case let .archive(program, position):
            openCatchup(program, position: position)
            return true
        case .live, .nothing:
            return false
        }
    }

    func openCatchup(_ program: EPGProgram, position: TimeInterval) {
        guard !didFinish else { return }
        catchupTask?.cancel()
        log.notice("catch-up: \(program.title) from \(Int(position))s")
        cover.isHidden = false
        cover.show(note: String(localized: "Catch-up"))
        catchupTask = Task { [weak self] in
            guard let self else { return }
            do {
                let archive = try await api.liveCatchup(channel, program: program, offset: 0)
                try Task.checkCancellation()
                loadTask?.cancel()
                endSession()
                let start = program.start.addingTimeInterval(TimeInterval(archive.offsetSeconds))
                let first = max(0, program.start.addingTimeInterval(position).timeIntervalSince(start))
                catchupArchive = LiveCatchupArchive(program: program, start: start, firstPosition: first)
                timeshiftWindow = nil
                applyTimeshiftMode()
                setInfoPanel(title: program.title, subtitle: channel.name, description: program.description)
                rebuildSubtitleMenu()
                log.info("catch-up: archive from \(archive.offsetSeconds)s for \(archive.durationSeconds)s, starting at \(Int(first))s")
                _ = try await engine.load(url: api.catchupStreamURL(archive, channel: channel, program: program),
                                          startPosition: first, options: baseLoadOptions())
                engine.play()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                log.error("catch-up failed: \(error.localizedDescription)")
                if inCatchupArchive {
                    catchupGoLive()
                } else {
                    hideCover()
                }
            }
        }
    }

    /// Back to the channel from the archive.
    func catchupGoLive() {
        guard !didFinish else { return }
        catchupTask?.cancel()
        guard inCatchupArchive else { return }
        log.notice("catch-up: back to live from \(Int(Date().timeIntervalSince(self.catchupPlayhead)))s behind")
        catchupArchive = nil
        retuneCount = 0
        setInfoPanel(title: program?.title ?? channel.name, subtitle: program == nil ? nil : channel.name,
                     description: program?.description)
        tune()
    }

    /// The archive ran out: on in a fresh one from there, or live.
    func catchupEnded() {
        guard let archive = catchupArchive, let window = channel.catchupWindow else { return }
        let position = max(engine.clock.currentTime, engine.duration)
        let playhead = archive.start.addingTimeInterval(position)
        switch LiveCatchupRules.continueAfter(playhead: playhead, played: position - archive.firstPosition, now: Date(),
                                              programs: catchupPrograms, archiveWindow: window) {
        case let .archive(program, position):
            log.notice("catch-up: archive ended \(Int(Date().timeIntervalSince(playhead)))s behind live; continuing")
            openCatchup(program, position: position)
        case .live, .nothing:
            catchupGoLive()
        }
    }

    /// On the software route: the archive's Play/Pause, Left / Right (10 s) and Up (live), and
    /// Left at the start of the timeshift window (or on a tune without one) into the archive.
    func handleCatchupPress(_ presses: Set<UIPress>) -> Bool {
        guard softwareSurfaceMounted, channel.catchupWindow != nil, let press = presses.first?.type else { return false }
        if inCatchupArchive {
            switch press {
            case .playPause: engine.togglePlayPause()
            case .leftArrow, .rightArrow:
                let step: TimeInterval = press == .leftArrow ? -10 : 10
                let target = min(max(0, engine.clock.currentTime + step), max(0, engine.duration - 1))
                Task { await engine.seek(to: target) }
            case .upArrow: catchupGoLive()
            default: return false
            }
            return true
        }
        guard press == .leftArrow else { return false }
        if timeshifting, let range = engine.clock.seekableLiveRange,
           engine.clock.currentTime - 10 > range.lowerBound + 2 { return false }
        return rewindIntoCatchup(to: catchupPlayhead.addingTimeInterval(-10))
    }
}

extension LivePlayerViewController: @MainActor AVPlayerViewControllerDelegate {
    /// AVKit's scrubber or skip reaching the start of the timeshift window: on back into the
    /// provider's archive from there.
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              timeToSeekAfterUserNavigatedFrom oldTime: CMTime, to targetTime: CMTime) -> CMTime {
        guard timeshifting, !inCatchupArchive, oldTime.isNumeric, targetTime.isNumeric,
              let range = player?.currentItem?.seekableTimeRanges.last?.timeRangeValue,
              targetTime.seconds <= range.start.seconds + 3 else { return targetTime }
        let date = catchupPlayhead.addingTimeInterval(min(targetTime.seconds - oldTime.seconds, -10))
        log.info("catch-up: rewind to the window's start (\(Int(targetTime.seconds - oldTime.seconds))s)")
        return rewindIntoCatchup(to: date) ? oldTime : targetTime
    }
}
