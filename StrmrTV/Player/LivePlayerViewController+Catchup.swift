import AetherEngine
import UIKit

/// The provider's archive playing in place of the channel.
struct LiveCatchupArchive {
    let program: EPGProgram
    /// The wall-clock time at the file's start (the provider may round it down a little).
    let start: Date
    /// Where playback started in the file.
    let firstPosition: TimeInterval
    /// Its first frame is up; until then the engine's clock is the previous session's.
    var started = false
}

/// Rewind into the provider's catch-up from a live channel that has it. A seek on the programme
/// bar (`+ProgrammeBar`) past what the player holds (the engine's timeshift window, or anything
/// on a tune without one) plays the provider's archive of the programme at that point instead;
/// Start Over plays it from the programme's start. The archive is always asked for from the
/// programme's start, and playback starts at the point wanted. The channel's session is stopped
/// meanwhile (a provider may allow one connection). An archive runs up to when it was asked for,
/// so at its end a fresh one carries on from there, into the next programme when this one has
/// ended; Go Live (or catching up with the edge) tunes the channel.
extension LivePlayerViewController {
    var inCatchupArchive: Bool { catchupArchive != nil }

    func hideCover() {
        cover.isHidden = true
        cover.show(note: nil)
        if usesProgrammeBar { scrub.hud.flash() }
    }

    /// The playhead as a wall-clock date: the archive's point, or now less how far behind live.
    var catchupPlayhead: Date {
        if let archive = catchupArchive {
            return archive.start.addingTimeInterval(archive.started ? engine.clock.currentTime : archive.firstPosition)
        }
        return Date().addingTimeInterval(-(timeshifting ? engine.clock.behindLiveSeconds : 0))
    }

    /// Loads the channel's guide around now, and again every 15 minutes, for the programmes an
    /// archive is asked for by.
    func startCatchupSchedule() {
        guard let window = channel.catchupWindow else { return }
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
            refreshProgrammeBar()
        } catch {
            log.error("catch-up: schedule failed: \(error.localizedDescription)")
        }
    }

    /// The programme at the playhead from its start.
    func startOver() {
        guard let program = LiveCatchupRules.program(at: catchupPlayhead, in: catchupPrograms), channel.canReplay(program) else {
            log.notice("catch-up: nothing to start over")
            return
        }
        openCatchup(program, position: 0)
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
        // A fresh engine session: loaded straight over the archive, the live window carried the
        // archive's length into its edge (the bar read half an hour behind at the live edge).
        engine.stop()
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
}

