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
