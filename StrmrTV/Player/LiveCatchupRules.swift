import Foundation

/// Where a rewind on a channel with provider catch-up lands, as wall-clock dates. An archive is
/// always asked for from its programme's start, so the transport bar spans the programme (start
/// to what had aired when it was asked for), and playback starts at the point wanted. Pure, so
/// it is unit-tested.
enum LiveCatchupRules {
    /// Within this of now counts as live.
    static let atLive: TimeInterval = 10
    /// An archive that would start this close to now isn't worth opening: live is as good.
    static let minimumBehind: TimeInterval = 60
    /// Less than this of an archive played before it ended: the provider has nothing more yet.
    static let minimumPlayed: TimeInterval = 5

    enum Seek: Equatable {
        case live
        /// The archive of `program` (from its start), playing from `position` seconds in.
        case archive(EPGProgram, position: TimeInterval)
        case nothing
    }

    /// Where a seek on the programme bar lands.
    enum Decision: Equatable {
        case live
        /// Inside what the player holds (the timeshift window, or the archive playing).
        case inPlayer(Date)
        case archive(EPGProgram, position: TimeInterval)
        case nothing
    }

    /// A seek to `date`: in place when the player holds it (`loaded`; live near its edge), else
    /// the archive there, or live when that is within `minimumBehind`. A rewind past what the
    /// player holds goes at least `minimumBehind` back (`rewindTarget`), so one press from a
    /// fresh tune reaches the archive rather than counting as live.
    static func decide(_ date: Date, now: Date, loaded: ClosedRange<Date>?, programs: [EPGProgram],
                       archiveWindow: TimeInterval) -> Decision {
        var date = date
        if let loaded, loaded.contains(date) { return now.timeIntervalSince(date) <= atLive ? .live : .inPlayer(date) }
        if loaded.map({ date < $0.lowerBound }) ?? true, date < now {
            date = rewindTarget(date, now: now)
        } else if now.timeIntervalSince(date) <= atLive {
            return .live
        }
        switch seek(to: date, now: now, programs: programs, archiveWindow: archiveWindow) {
        case .live: return .live
        case let .archive(program, position): return .archive(program, position: position)
        case .nothing: return .nothing
        }
    }

    /// The programme airing at `date`: the last one to start at or before it that hasn't stopped.
    static func program(at date: Date, in programs: [EPGProgram]) -> EPGProgram? {
        programs.last { $0.start <= date && date < $0.stop }
    }

    static func seek(to date: Date, now: Date, programs: [EPGProgram], archiveWindow: TimeInterval) -> Seek {
        let behind = now.timeIntervalSince(date)
        if behind < minimumBehind { return .live }
        if behind > archiveWindow { return .nothing }
        guard let program = program(at: date, in: programs) else { return .nothing }
        return .archive(program, position: date.timeIntervalSince(program.start))
    }

    /// A rewind past what the player holds (the start of the timeshift window, or a tune without
    /// one), asked for at `date`: at least `minimumBehind` back, so it opens the archive even when
    /// the window holds only a few seconds (a fresh tune) rather than counting as live.
    static func rewindTarget(_ date: Date, now: Date) -> Date {
        min(date, now.addingTimeInterval(-minimumBehind))
    }

    /// An archive played to its end at `playhead` (it ran up to what had aired when it was asked
    /// for): on in a fresh one from there, into the next programme if this one has ended, or live
    /// once that is now.
    static func continueAfter(playhead: Date, played: TimeInterval, now: Date, programs: [EPGProgram],
                              archiveWindow: TimeInterval) -> Seek {
        guard played >= minimumPlayed else { return .live }
        if case let .archive(program, position) = seek(to: playhead, now: now, programs: programs, archiveWindow: archiveWindow) {
            return .archive(program, position: position)
        }
        return .live
    }
}
