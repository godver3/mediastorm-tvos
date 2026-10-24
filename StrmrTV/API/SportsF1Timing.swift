import Foundation

/// A driver's line in an F1 timing archive (Expo `f1Drivers`); "" or nil where nothing was reported.
struct SportsF1Driver: Equatable, Identifiable {
    /// The racing number, which keys a driver throughout the archive.
    let id: String
    let name: String
    let abbreviation: String
    let team: String
    let position: Int?
    let laps: Int?
    let knockedOut: Bool
    /// The best laps of Q1, Q2 and Q3.
    let qualifyingTimes: [String]
    let bestLap: String
    let lastLap: String
    let interval: String
    let pitStops: Int?
    let retired: Bool
    let stopped: Bool
    let gap: String
    let inPit: Bool
    /// S1–S3 of the latest lap; empty when the archive has no sectors.
    let sectors: [String]
    let stints: [SportsF1Stint]

    /// What to flag about the car: retired, stopped, in the pit or knocked out.
    var state: String? {
        if retired { return String(localized: "Retired") }
        if stopped { return String(localized: "Stopped") }
        if inPit { return String(localized: "In pit") }
        if knockedOut { return String(localized: "Knocked out") }
        return nil
    }
}

/// A tyre stint: compound, the set's age at the end, and the laps run on it (a used set's earlier laps taken off).
struct SportsF1Stint: Equatable, Identifiable {
    let id: String
    let compound: String
    let age: Int?
    let laps: Int?
    let used: Bool
}

/// A race-control message.
struct SportsF1Message: Equatable, Identifiable {
    let id: String
    let message: String
    let lap: Int?
    let utc: String
    let flag: String
    let category: String
    let driver: String
}

/// The qualifying part an archive ends in, and how many entries were still running in it.
struct SportsF1Qualifying: Equatable {
    let part: Int
    let remaining: Int?
}

/// Reads an F1 timing archive's raw channels (Expo `sports-f1.ts`). The feed keys lists by
/// index or as arrays; both read the same. Missing values stay missing, never zero.
enum SportsF1Timing {
    static func drivers(_ archive: SportsF1Archive) -> [SportsF1Driver] {
        guard let channels = archive.channels else { return [] }
        let timing = fields(channels["TimingData"]?["Lines"])
        let app = fields(channels["TimingAppData"]?["Lines"])
        return list(channels["DriverList"]).filter { truthy(fields($0.value)["RacingNumber"]) }.map { id, raw in
            let driver = fields(raw)
            let line = fields(timing[id])
            let sectors = fields(line["Sectors"])
            let best = fields(line["BestLapTimes"])
            return SportsF1Driver(
                id: id, name: text(driver["FullName"]), abbreviation: text(driver["Tla"]), team: text(driver["TeamName"]),
                position: number(line["Position"]), laps: number(line["NumberOfLaps"]), knockedOut: isTrue(line["KnockedOut"]),
                qualifyingTimes: (0...2).map { value(best["\($0)"]) }, bestLap: value(line["BestLapTime"]),
                lastLap: value(line["LastLapTime"]), interval: value(line["IntervalToPositionAhead"]),
                pitStops: number(line["NumberOfPitStops"]), retired: isTrue(line["Retired"]), stopped: isTrue(line["Stopped"]),
                gap: text(line["GapToLeader"]), inPit: isTrue(line["InPit"]),
                sectors: sectors.isEmpty ? [] : (0...2).map { value(sectors["\($0)"]) },
                stints: list(fields(app[id])["Stints"]).map { stint($0.key, fields($0.value)) })
        }
        .sorted { a, b in
            let first = a.position ?? 999, second = b.position ?? 999
            return first != second ? first < second : order(a.id, b.id)
        }
    }

    /// Race-control messages, newest first.
    static func messages(_ archive: SportsF1Archive) -> [SportsF1Message] {
        list(archive.channels?["RaceControlMessages"]?["Messages"]).map { id, raw in
            let m = fields(raw)
            return SportsF1Message(id: id, message: text(m["Message"]), lap: number(m["Lap"]), utc: text(m["Utc"]),
                                   flag: text(m["Flag"]), category: text(m["Category"]), driver: text(m["RacingNumber"]))
        }
        .filter { !$0.message.isEmpty }
        .sorted { $0.utc != $1.utc ? $0.utc > $1.utc : (Double($0.id) ?? 0) > (Double($1.id) ?? 0) }
    }

    /// "Air 24°C · Track 38°C · No rainfall reported", or "" when not reported.
    static func weather(_ archive: SportsF1Archive) -> String {
        let w = fields(archive.channels?["WeatherData"])
        let rain: String? = switch text(w["Rainfall"]) {
        case "1": String(localized: "Rain reported")
        case "0": String(localized: "No rainfall reported")
        default: nil
        }
        return [present(w["AirTemp"]).map { "Air \(text($0))°C" }, present(w["TrackTemp"]).map { "Track \(text($0))°C" }, rain]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The qualifying part a qualifying archive ends in (Expo `f1Qualifying`); nil for other sessions.
    static func qualifying(_ archive: SportsF1Archive) -> SportsF1Qualifying? {
        guard (archive.sessionName ?? "").localizedCaseInsensitiveContains("qualifying") else { return nil }
        let timing = fields(archive.channels?["TimingData"])
        guard let part = number(timing["SessionPart"]), (1...3).contains(part) else { return nil }
        return SportsF1Qualifying(part: part, remaining: number(fields(timing["NoEntries"])["\(part - 1)"]))
    }

    private static func stint(_ key: String, _ stint: [String: SportsJSON]) -> SportsF1Stint {
        let total = number(stint["TotalLaps"]), before = number(stint["StartLaps"])
        let laps = total.flatMap { total in before.flatMap { total >= $0 ? total - $0 : nil } }
        let compound = text(stint["Compound"])
        return SportsF1Stint(id: key, compound: compound.isEmpty ? "UNKNOWN" : compound, age: total, laps: laps,
                             used: (before ?? 0) > 0)
    }

    /// An object's fields, or an array's items keyed by index (the feed sends either).
    private static func fields(_ json: SportsJSON?) -> [String: SportsJSON] {
        switch json {
        case let .object(fields): fields
        case let .array(items): Dictionary(uniqueKeysWithValues: items.enumerated().map { ("\($0.offset)", $0.element) })
        default: [:]
        }
    }

    /// `fields` in feed order: numeric keys by number, others by name.
    private static func list(_ json: SportsJSON?) -> [(key: String, value: SportsJSON)] {
        fields(json).sorted { order($0.key, $1.key) }.map { (key: $0.key, value: $0.value) }
    }

    private static func order(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): x < y
        case (.some, nil): true
        case (nil, .some): false
        default: a < b
        }
    }

    /// A `{"Value": …}` reading's text.
    private static func value(_ json: SportsJSON?) -> String { text(fields(json)["Value"]) }

    private static func present(_ json: SportsJSON?) -> SportsJSON? {
        if json == nil || json == .null { return nil }
        return json
    }

    /// A string or number as text; anything else (booleans included) is "".
    private static func text(_ json: SportsJSON?) -> String {
        switch json {
        case let .string(text): text
        case let .number(number): number.rounded() == number && abs(number) < 1e15 ? String(Int(number)) : String(number)
        default: ""
        }
    }

    /// A non-negative number, from a number or numeric text; nothing for blanks and booleans.
    private static func number(_ json: SportsJSON?) -> Int? {
        let raw = text(json).trimmingCharacters(in: .whitespaces)
        guard let value = Double(raw), value.isFinite, value >= 0 else { return nil }
        return Int(value)
    }

    private static func isTrue(_ json: SportsJSON?) -> Bool { json == .bool(true) }

    /// JavaScript truthiness of a primitive: a non-empty string, a non-zero number or true.
    private static func truthy(_ json: SportsJSON?) -> Bool {
        switch json {
        case let .string(text): !text.isEmpty
        case let .bool(value): value
        case let .number(number): number != 0
        default: false
        }
    }
}
