import Foundation
import CoreGraphics

/// `GET /api/sports/races`: the race weekends in the providers' window, each with its sessions,
/// and every series' feed state (Expo `SportsRaceBoard`). Both lists are lenient: a bad item is
/// skipped and `null` is empty.
struct SportsRaceBoard: Decodable, Hashable, Sendable {
    var events: [SportsRaceEvent] = []
    var leagues: [SportsRaceFeed] = []

    private enum CodingKeys: String, CodingKey { case events, leagues }

    init(events: [SportsRaceEvent] = [], leagues: [SportsRaceFeed] = []) {
        self.events = events
        self.leagues = leagues
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = c.sportsList(SportsRaceEvent.self, .events)
        leagues = c.sportsList(SportsRaceFeed.self, .leagues)
    }

    /// A series is stale or unavailable: the hub says racing updates are delayed.
    var delayed: Bool { leagues.contains { $0.stale || $0.unavailable } }

    /// The weekend `id` names or holds as a session, with the session to open on (nil: the
    /// weekend's default). Expo `resolveRaceSelection`.
    func resolve(_ id: String) -> (weekend: SportsRaceEvent, session: String?)? {
        for event in events {
            if event.id == id { return (event, event.isSession ? event.id : nil) }
            if let session = event.subEvents.first(where: { $0.id == id }) { return (event, session.id) }
        }
        return nil
    }
}

/// One series' feed state on the race board.
struct SportsRaceFeed: Decodable, Hashable {
    var league = ""
    var stale = false
    var unavailable = false
    var updatedAt: String?

    private enum CodingKeys: String, CodingKey { case league, stale, unavailable, updatedAt }

    init(league: String, stale: Bool = false, unavailable: Bool = false, updatedAt: String? = nil) {
        self.league = league
        self.stale = stale
        self.unavailable = unavailable
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        league = try c.decodeIfPresent(String.self, forKey: .league) ?? ""
        stale = try c.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        unavailable = try c.decodeIfPresent(Bool.self, forKey: .unavailable) ?? false
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

/// A race weekend (`eventKind` `race`, its sessions in `subEvents`) or one session of it
/// (`race-session`): Expo `SportsRaceEvent`, the backend's generalized `SportsEvent`. A weekend
/// has no participants; a session's are its entries or its classification.
struct SportsRaceEvent: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var providerEventId = ""
    var sessionId: String?
    var sessionType: String?
    var title = ""
    var league = ""
    var eventKind = "race"
    var startTime = ""
    var status = "scheduled"
    var statusDetail: String?
    var venue: String?
    var broadcasts: [String]?
    var participants: [SportsRaceDriver] = []
    var subEvents: [SportsRaceEvent] = []
    var updatedAt: String?
    var stale = false
    var circuit: SportsCircuit?
    /// An F1 timing archive a recorded capture embeds; the server sends it from its own endpoint.
    var f1Archive: SportsF1Archive?

    private enum CodingKeys: String, CodingKey {
        case id, providerEventId, sessionId, sessionType, title, league, eventKind, startTime, status, statusDetail, venue,
             broadcasts, participants, subEvents, updatedAt, stale, circuit, f1Archive
    }

    init(id: String, providerEventId: String = "", sessionId: String? = nil, sessionType: String? = nil, title: String = "",
         league: String = "", eventKind: String = "race", startTime: String = "", status: String = "scheduled",
         statusDetail: String? = nil, venue: String? = nil, participants: [SportsRaceDriver] = [],
         subEvents: [SportsRaceEvent] = []) {
        self.id = id
        self.providerEventId = providerEventId
        self.sessionId = sessionId
        self.sessionType = sessionType
        self.title = title
        self.league = league
        self.eventKind = eventKind
        self.startTime = startTime
        self.status = status
        self.statusDetail = statusDetail
        self.venue = venue
        self.participants = participants
        self.subEvents = subEvents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        providerEventId = try c.decodeIfPresent(String.self, forKey: .providerEventId) ?? ""
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        sessionType = try c.decodeIfPresent(String.self, forKey: .sessionType)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        league = try c.decodeIfPresent(String.self, forKey: .league) ?? ""
        eventKind = try c.decodeIfPresent(String.self, forKey: .eventKind) ?? "race"
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "scheduled"
        statusDetail = try c.decodeIfPresent(String.self, forKey: .statusDetail)
        venue = try c.decodeIfPresent(String.self, forKey: .venue)
        broadcasts = c.sportsValue([String].self, .broadcasts)
        participants = c.sportsList(SportsRaceDriver.self, .participants)
        subEvents = c.sportsList(SportsRaceEvent.self, .subEvents)
        updatedAt = c.sportsValue(String.self, .updatedAt)
        stale = c.sportsValue(Bool.self, .stale) ?? false
        circuit = c.sportsValue(SportsCircuit.self, .circuit)
        f1Archive = c.sportsValue(SportsF1Archive.self, .f1Archive)
    }

    var start: Date? { Self.date(startTime) }
    /// Go's zero time (no update yet) is none.
    var updated: Date? { updatedAt.flatMap(Self.date) }

    /// An ISO 8601 time; Go's zero time ("0001-01-01T00:00:00Z") is none.
    static func date(_ text: String) -> Date? {
        SportsGame.date(text).flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil }
    }

    var lifecycle: SportsLifecycle { SportsLifecycle(status: status, detail: statusDetail) }
    var isLive: Bool { status == "live" }
    var isFinal: Bool { status == "final" }

    /// A single session rather than a weekend.
    var isSession: Bool { eventKind == "race-session" && subEvents.isEmpty }

    /// MotoGP lists riders; the other series drivers.
    var riders: Bool { league == "motogp" }

    /// A weekend's sessions in start order (Expo's session picker); a lone session is its own.
    var sessions: [SportsRaceEvent] {
        isSession ? [self] : subEvents.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    /// The session a weekend opens on: the live one, else the last race, else the last session
    /// (Expo `defaultRaceSession`).
    var defaultSession: SportsRaceEvent? {
        if isSession { return self }
        return subEvents.first(where: \.isLive)
            ?? subEvents.last { ($0.sessionType ?? "").range(of: #"^race\s*\d*$"#, options: [.regularExpression, .caseInsensitive]) != nil }
            ?? subEvents.last
    }

    /// Where it runs: the session's venue, the weekend's, or the circuit's name.
    func place(_ weekend: SportsRaceEvent?) -> String? {
        [venue, weekend?.venue, weekend?.circuit?.name]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}

/// An entry of a session, with its position and timing as the provider reported them (Expo
/// `RaceDriver`). A field of the wrong type skips the entry, never the session.
struct SportsRaceDriver: Decodable, Identifiable, Hashable {
    var id = ""
    var name = ""
    var abbreviation: String?
    var position: Int?
    var winner = false
    var number: String?
    var team: String?
    /// "Classified", "Retired", "DNF"…; "Classified" goes unsaid.
    var result: String?
    var statistics: [SportsRaceStatistic] = []

    private enum CodingKeys: String, CodingKey { case id, name, abbreviation, position, winner, number, team, result, statistics }

    init(id: String, name: String, position: Int? = nil, number: String? = nil, team: String? = nil, result: String? = nil,
         statistics: [SportsRaceStatistic] = []) {
        self.id = id
        self.name = name
        self.position = position
        self.number = number
        self.team = team
        self.result = result
        self.statistics = statistics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        abbreviation = try c.decodeIfPresent(String.self, forKey: .abbreviation)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        winner = try c.decodeIfPresent(Bool.self, forKey: .winner) ?? false
        number = try c.decodeIfPresent(String.self, forKey: .number)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        result = try c.decodeIfPresent(String.self, forKey: .result)
        statistics = c.sportsList(SportsRaceStatistic.self, .statistics)
    }

    /// A statistic's value, trimmed; nil when missing or blank.
    func stat(_ name: String) -> String? {
        statistics.first { $0.name == name }.flatMap { Self.filled($0.value) }
    }

    /// The result worth showing: anything but "Classified".
    var outcome: String? { Self.filled(result).flatMap { $0 == "Classified" ? nil : $0 } }

    static func filled(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// A labelled figure of an entry (`lapsCompleted`, `behindTime`, `fastestLap`, `qual1TimeMS`…).
struct SportsRaceStatistic: Decodable, Hashable {
    var name = ""
    var label = ""
    var value = ""

    private enum CodingKeys: String, CodingKey { case name, label, value }

    init(name: String, label: String, value: String) {
        self.name = name
        self.label = label
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.sportsValue(String.self, .name) ?? ""
        label = c.sportsValue(String.self, .label) ?? ""
        value = c.sportsText(.value) ?? ""
    }
}

/// Community reference geometry for a circuit as `[longitude, latitude]` points, never live
/// tracking (Expo `SportsCircuit`).
struct SportsCircuit: Decodable, Hashable {
    var id = ""
    var name = ""
    var location = ""
    var referenceLengthMeters = 0
    var coordinates: [[Double]] = []
    var sourceUrl = ""
    var attribution = ""

    private enum CodingKeys: String, CodingKey { case id, name, location, referenceLengthMeters, coordinates, sourceUrl, attribution }

    init(coordinates: [[Double]]) { self.coordinates = coordinates }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.sportsValue(String.self, .id) ?? ""
        name = c.sportsValue(String.self, .name) ?? ""
        location = c.sportsValue(String.self, .location) ?? ""
        referenceLengthMeters = c.sportsValue(Int.self, .referenceLengthMeters) ?? 0
        coordinates = c.sportsValue([[Double]].self, .coordinates) ?? []
        sourceUrl = c.sportsValue(String.self, .sourceUrl) ?? ""
        attribution = c.sportsValue(String.self, .attribution) ?? ""
    }

    /// The outline projected flat around its own latitude (east right, north up), shifted to
    /// start at 0,0; nil for too few, too many or out-of-range points (Expo `projectCircuit`).
    func outline() -> SportsCircuitOutline? {
        guard (3...2000).contains(coordinates.count) else { return nil }
        guard coordinates.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) && abs($0[0]) <= 180 && abs($0[1]) <= 90 })
        else { return nil }
        let latitude = coordinates.map { $0[1] }.reduce(0, +) / Double(coordinates.count)
        let stretch = cos(latitude * .pi / 180)
        let flat = coordinates.map { CGPoint(x: $0[0] * stretch, y: -$0[1]) }
        let minX = flat.map(\.x).min()!, minY = flat.map(\.y).min()!
        let width = flat.map(\.x).max()! - minX, height = flat.map(\.y).max()! - minY
        guard width > 0, height > 0 else { return nil }
        return SportsCircuitOutline(points: flat.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }, width: width, height: height)
    }
}

/// A circuit's projected outline: points within `width` × `height`, y growing south.
struct SportsCircuitOutline: Equatable {
    let points: [CGPoint]
    let width: CGFloat
    let height: CGFloat
}
