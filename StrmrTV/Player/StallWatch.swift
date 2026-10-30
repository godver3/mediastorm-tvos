import Foundation

/// When a movie or episode should move to another source on its own
/// (`PlayerViewController+AutoSwitch`): it is meant to be playing but the playhead has not moved
/// for `stuckLimit` (`settleLimit` while it starts or after a seek), or it has stalled
/// `stallCount` times within `stallWindow`, however short each stall. Sampled once a second.
struct StallWatch {
    enum Trigger: Equatable {
        case stuck(seconds: Int)
        case repeatedStalls(count: Int)

        var reason: String {
            switch self {
            case let .stuck(seconds): "stuck \(seconds)s"
            case let .repeatedStalls(count): "\(count) stalls in \(Int(StallWatch.stallWindow))s"
            }
        }
    }

    static let stuckLimit: TimeInterval = 10
    /// Before playback first moves, and after a seek, a slow start is allowed longer.
    static let settleLimit: TimeInterval = 20
    /// A still playhead this long counts as one stall.
    static let stallThreshold: TimeInterval = 2
    static let stallCount = 3
    static let stallWindow: TimeInterval = 120
    /// A jump bigger than this between samples is a seek, not playback.
    static let seekJump: TimeInterval = 4

    private var lastPosition: Double?
    private var lastSampleAt: Date?
    private var stillSince: Date?
    private var stallCounted = false
    private var stalls: [Date] = []
    /// Starting up or landing a seek: until the playhead moves again.
    private var settling = true

    /// Starts over, as at the start of playback (after a switch that found nothing to switch to).
    mutating func reset() {
        self = StallWatch()
    }

    /// `active`: playback is meant to be moving (loading or playing; not paused, seeking or ended).
    mutating func sample(position: Double, active: Bool, now: Date = Date()) -> Trigger? {
        defer {
            lastPosition = position
            lastSampleAt = now
        }
        guard active else {
            stillSince = nil
            stallCounted = false
            return nil
        }
        if let last = lastPosition, let lastAt = lastSampleAt {
            let moved = position - last
            if abs(moved - now.timeIntervalSince(lastAt)) > Self.seekJump {
                settling = true
                stillSince = nil
                stallCounted = false
                return nil
            }
            if moved > 0.05 {
                settling = false
                stillSince = nil
                stallCounted = false
                return nil
            }
        }
        let since = stillSince ?? now
        stillSince = since
        let still = now.timeIntervalSince(since)
        if !settling, !stallCounted, still >= Self.stallThreshold {
            stallCounted = true
            stalls = stalls.filter { now.timeIntervalSince($0) < Self.stallWindow } + [now]
            if stalls.count >= Self.stallCount { return .repeatedStalls(count: stalls.count) }
        }
        if still >= (settling ? Self.settleLimit : Self.stuckLimit) {
            return .stuck(seconds: Int(still))
        }
        return nil
    }
}
