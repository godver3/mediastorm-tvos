import Foundation

/// `GET /api/sports/motogp/standings` and `/motogp/circuit/{providerEventId}`: the organizer's
/// riders' championship or circuit facts (Expo `MotoGPStandings`, `MotoGPCircuitGuide`; the
/// backend's `MotoGPEnrichment`).
struct SportsMotoGPEnrichment: Decodable, Hashable {
    var captured = false
    /// `available`, `stale` or `unavailable`.
    var state = "unavailable"
    var season: Int?
    var source = ""
    var sourceUrl = ""
    var updatedAt: String?
    var reason: String?
    var standings: [SportsMotoGPRider] = []
    var circuit: SportsMotoGPCircuit?

    private enum CodingKeys: String, CodingKey {
        case captured, state, season, source, sourceUrl, updatedAt, reason, standings, circuit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        captured = c.sportsValue(Bool.self, .captured) ?? false
        state = c.sportsValue(String.self, .state) ?? "unavailable"
        season = c.sportsValue(Int.self, .season)
        source = c.sportsValue(String.self, .source) ?? ""
        sourceUrl = c.sportsValue(String.self, .sourceUrl) ?? ""
        updatedAt = c.sportsValue(String.self, .updatedAt)
        reason = c.sportsValue(String.self, .reason)
        standings = c.sportsList(SportsMotoGPRider.self, .standings)
        circuit = c.sportsValue(SportsMotoGPCircuit.self, .circuit)
    }

    var stale: Bool { state == "stale" }
    var unavailable: Bool { state == "unavailable" }
}

/// A rider's championship line; MotoGP awards half points, so `points` can be fractional.
struct SportsMotoGPRider: Decodable, Hashable, Identifiable {
    var riderId = ""
    var name = ""
    var number: Int?
    var team: String?
    var manufacturer: String?
    var position: Int?
    var points: Double?
    var wins: Int?
    var podiums: Int?

    var id: String { riderId.isEmpty ? name : riderId }

    private enum CodingKeys: String, CodingKey {
        case riderId, name, number, team, manufacturer = "constructor", position, points, wins, podiums
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        riderId = try c.decodeIfPresent(String.self, forKey: .riderId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        number = try c.decodeIfPresent(Int.self, forKey: .number)
        team = try c.decodeIfPresent(String.self, forKey: .team)
        manufacturer = try c.decodeIfPresent(String.self, forKey: .manufacturer)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        points = try c.decodeIfPresent(Double.self, forKey: .points)
        wins = try c.decodeIfPresent(Int.self, forKey: .wins)
        podiums = try c.decodeIfPresent(Int.self, forKey: .podiums)
    }

    /// Whole points without a decimal; MotoGP's half points keep theirs.
    var pointsText: String {
        guard let points else { return "—" }
        return points.rounded() == points ? String(Int(points)) : String(points)
    }
}

/// The organizer's facts about a MotoGP circuit and its published diagram.
struct SportsMotoGPCircuit: Decodable, Hashable {
    var id = ""
    var name = ""
    var mapUrl: String?
    var lengthMeters: Int?
    var leftCorners: Int?
    var rightCorners: Int?
    var longestStraightMeters: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, mapUrl, lengthMeters, leftCorners, rightCorners, longestStraightMeters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.sportsValue(String.self, .id) ?? ""
        name = c.sportsValue(String.self, .name) ?? ""
        mapUrl = c.sportsValue(String.self, .mapUrl)
        lengthMeters = c.sportsValue(Int.self, .lengthMeters)
        leftCorners = c.sportsValue(Int.self, .leftCorners)
        rightCorners = c.sportsValue(Int.self, .rightCorners)
        longestStraightMeters = c.sportsValue(Int.self, .longestStraightMeters)
    }

    /// The diagram, https only.
    var map: URL? { mapUrl.flatMap { $0.hasPrefix("https://") ? URL(string: $0) : nil } }
}

/// `GET /api/sports/f1/archive/{providerEventId}/{sessionId}`: F1's timing feed of a finished
/// session as captured channels (`DriverList`, `TimingData`, `TimingAppData`,
/// `RaceControlMessages`, `WeatherData`…), read by `SportsF1Timing`; never a live feed (Expo
/// `F1Archive`).
struct SportsF1Archive: Decodable, Hashable {
    var state = "unavailable"
    /// `archive` (the final snapshot) or `recorded` (frozen at `capturedElapsed`).
    var mode = "archive"
    var eventId = ""
    var sessionName: String?
    var sourceUrl: String?
    var checkedAt: String?
    var capturedElapsed: String?
    var reason: String?
    var channels: SportsJSON?

    private enum CodingKeys: String, CodingKey {
        case state, mode, eventId, sessionName, sourceUrl, checkedAt, capturedElapsed, reason, channels
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.sportsValue(String.self, .state) ?? "unavailable"
        mode = c.sportsValue(String.self, .mode) ?? "archive"
        eventId = c.sportsValue(String.self, .eventId) ?? ""
        sessionName = c.sportsValue(String.self, .sessionName)
        sourceUrl = c.sportsValue(String.self, .sourceUrl)
        checkedAt = c.sportsValue(String.self, .checkedAt)
        capturedElapsed = c.sportsValue(String.self, .capturedElapsed)
        reason = c.sportsValue(String.self, .reason)
        channels = c.sportsValue(SportsJSON.self, .channels)
    }

    var available: Bool { state == "available" }
    var recorded: Bool { mode == "recorded" }
}

/// Any JSON value, for feeds read field by field (the F1 archive's channels).
enum SportsJSON: Decodable, Hashable {
    case object([String: SportsJSON])
    case array([SportsJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode([String: SportsJSON].self) { self = .object(value) }
        else { self = .array(try c.decode([SportsJSON].self)) }
    }

    subscript(key: String) -> SportsJSON? {
        if case let .object(fields) = self { return fields[key] }
        return nil
    }
}
