import Foundation

/// A race session listed on the Sports hub, with its weekend (Expo `HubCard` of kind `race`).
struct SportsRaceListing: Hashable {
    let session: SportsRaceEvent
    let weekend: SportsRaceEvent

    var lifecycle: SportsLifecycle { session.lifecycle }

    /// One card per weekend in each lifecycle, so the key holds both.
    var key: String { "race:\(weekend.id):\(lifecycle.key)" }

    /// The entries a card lists by position: the top two, three once final.
    var leaders: [SportsRaceDriver] {
        Array(session.participants.filter { $0.position != nil }.sorted { $0.position! < $1.position! }
            .prefix(session.isFinal ? 3 : 2))
    }
}

/// The Sports hub's racing rules: which sessions get a card on a day, their follow order, and
/// how often the race board reloads (Expo `SportsHubTV` race items, `useSportsHubRaces`).
enum SportsRaceHub {
    static let motorsport = "motorsport"

    /// Seconds to the next board load after a failed one.
    static let retrySeconds = 30

    /// The sessions starting within the interval (the hub's local day) of the series `include`
    /// accepts, as one card per weekend in each lifecycle: the earliest session not yet under
    /// way, or the latest live or finished one. A weekend whose sessions aren't listed stands for
    /// itself; listings keep the board's order.
    static func listings(_ board: SportsRaceBoard, in day: DateInterval, include: (String) -> Bool) -> [SportsRaceListing] {
        var keys: [String] = []
        var chosen: [String: SportsRaceListing] = [:]
        for weekend in board.events where include(weekend.league) {
            for session in weekend.subEvents.isEmpty ? [weekend] : weekend.subEvents {
                guard let start = session.start, start >= day.start, start < day.end else { continue }
                let listing = SportsRaceListing(session: session, weekend: weekend)
                guard let previous = chosen[listing.key]?.session.start else {
                    keys.append(listing.key)
                    chosen[listing.key] = listing
                    continue
                }
                let earlier = start < previous
                let upcoming = !session.isLive && !session.isFinal
                if upcoming ? earlier : !earlier { chosen[listing.key] = listing }
            }
        }
        return keys.compactMap { chosen[$0] }
    }

    /// Seconds until the board reloads: 30 while a session is live, a series is stale or
    /// unavailable, or nothing came back; otherwise 60.
    static func refreshSeconds(_ board: SportsRaceBoard) -> Int {
        let live = board.events.contains { $0.isLive || $0.subEvents.contains(where: \.isLive) }
        return live || board.delayed || board.events.isEmpty ? 30 : 60
    }

    /// The id a followed series is saved under, shared with the Expo app (`racingFollowId`).
    static func followID(_ league: String) -> String { SportsLeague.followAliases[league] ?? league }

    /// Following shows a series followed by itself or through motorsport as a pinned sport.
    static func isFollowed(_ league: String, competitions: [String], pinned: [String]) -> Bool {
        competitions.contains(followID(league)) || pinned.contains(motorsport)
    }

    /// Where a race card sorts within its row (Expo `priority`): followed series first, in
    /// follow order, then motorsport as a pinned sport, then everything else.
    static func followRank(_ league: String, competitions: [String], pinned: [String]) -> Int {
        if let followed = competitions.firstIndex(of: followID(league)) { return followed }
        if let pin = pinned.firstIndex(of: motorsport) { return competitions.count + pin }
        return Int.max
    }
}

extension SportsLeague {
    /// A racing series of the catalog: Formula 1, NASCAR Cup, IndyCar, MotoGP and ESPN's other series.
    var isRacing: Bool { sport == "racing" || SportsRaceFormat.seriesNames[id] != nil || id.hasPrefix("espn:racing:") }
}

extension SportsLifecycle {
    /// A stable name for keys.
    var key: String {
        switch self {
        case .scheduled: "scheduled"
        case .live: "live"
        case .final: "final"
        case .delayed: "delayed"
        case .postponed: "postponed"
        case .canceled: "canceled"
        }
    }
}
