import Foundation

/// Race texts shared by the hub card and the race page: timing labels (Expo `SportsRaceTable`),
/// session states and snapshot lines (`SportsRaceDetailTV`), card lines (`SportsHubShowcase`),
/// card titles (`sports-event-card-title.ts`) and dates (`raceDate`).
enum SportsRaceFormat {
    /// Series names for a catalog without them (Expo `RACING_LEAGUES`).
    static let seriesNames = ["f1": "Formula 1", "nascar": "NASCAR Cup", "indycar": "IndyCar", "motogp": "MotoGP"]

    /// The gap to the leader, else laps behind, else session time or best lap (Expo `raceTimingLabel`).
    static func timing(_ driver: SportsRaceDriver) -> String? {
        if let gap = driver.stat("behindTime") { return gap }
        if let laps = lapsBehind(driver) {
            return laps == 1 ? String(localized: "1 lap behind") : String(localized: "\(laps) laps behind")
        }
        return driver.stat("totalTime") ?? driver.stat("fastestLap")
    }

    /// What `timing` shows: "Gap", "Time" or "Best lap" (Expo `raceTimingKind`).
    static func timingKind(_ driver: SportsRaceDriver) -> String? {
        if driver.stat("behindTime") != nil || lapsBehind(driver) != nil { return String(localized: "Gap") }
        if driver.stat("totalTime") != nil { return String(localized: "Time") }
        if driver.stat("fastestLap") != nil { return String(localized: "Best lap") }
        return nil
    }

    /// A card's figure for an entry: its timing, else a result other than "Classified".
    static func cardValue(_ driver: SportsRaceDriver) -> String? { timing(driver) ?? driver.outcome }

    private static func lapsBehind(_ driver: SportsRaceDriver) -> Int? {
        guard let text = driver.stat("behindLaps"), matches(#"^-?\d+$"#, text), let laps = Int(text), laps != 0 else { return nil }
        return abs(laps)
    }

    /// Qualifying shows best laps and the Q1–Q3 times.
    static func isQualifying(_ session: SportsRaceEvent?) -> Bool {
        (session?.sessionType ?? "").localizedCaseInsensitiveContains("qual")
    }

    /// A weekend's title on a card: "… Grand Prix of X" shortened to "Grand Prix of X", and that
    /// or a shouting title title-cased (Expo `sportsEventCardTitle`). Pages keep the full title.
    static func cardTitle(_ title: String) -> String {
        let grandPrix = title.range(of: #"\bgrand prix of\s+(.+)$"#, options: [.regularExpression, .caseInsensitive])
        let short: String
        if let grandPrix {
            let rest = title[grandPrix].replacingOccurrences(of: #"^grand prix of\s+"#, with: "",
                                                             options: [.regularExpression, .caseInsensitive])
            short = "Grand Prix of \(rest)"
        } else {
            short = title
        }
        if grandPrix == nil, short != short.uppercased() { return short.trimmingCharacters(in: .whitespaces) }
        let lower = short.lowercased()
        let words = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
        var result = ""
        var cursor = lower.startIndex
        for match in words.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            guard let range = Range(match.range, in: lower) else { continue }
            result += lower[cursor..<range.lowerBound]
            let word = String(lower[range])
            if smallWords.contains(word), range.lowerBound > lower.startIndex { result += word }
            else if acronyms.contains(word) { result += word.uppercased() }
            else { result += word.prefix(1).uppercased() + word.dropFirst() }
            cursor = range.upperBound
        }
        result += lower[cursor...]
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// "Results", "Live", "Scheduled", "Cancelled", "Postponed" or "Recorded snapshot" (Expo `sessionState`).
    static func sessionState(_ session: SportsRaceEvent) -> String {
        let detail = session.statusDetail ?? ""
        if session.f1Archive?.recorded == true { return String(localized: "Recorded snapshot") }
        if matches(#"\bcancell?ed\b"#, detail) { return String(localized: "Cancelled") }
        if matches(#"\bpostponed\b"#, detail) { return String(localized: "Postponed") }
        if session.isFinal { return String(localized: "Results") }
        if session.isLive { return String(localized: "Live") }
        return String(localized: "Scheduled")
    }

    /// A card's progress line: the local start time; a delay or postponement before the start;
    /// then the provider's status, or "Results hidden" under Hide Scores.
    static func progress(_ session: SportsRaceEvent, spoilers: Bool) -> String {
        let detail = SportsRaceDriver.filled(session.statusDetail)
        if session.lifecycle == .scheduled { return time(session.start) }
        if !session.isLive && !session.isFinal { return detail ?? time(session.start) }
        if spoilers { return String(localized: "Results hidden") }
        return detail ?? (session.isFinal ? String(localized: "Session complete") : String(localized: "Session in progress"))
    }

    /// What a card says where its leaders go when there are none to show.
    static func cardEmpty(_ session: SportsRaceEvent, spoilers: Bool) -> String {
        if !session.isLive && !session.isFinal { return String(localized: "Scheduled start") }
        if spoilers { return String(localized: "Hide Scores is on") }
        return session.isFinal ? String(localized: "Results unavailable") : String(localized: "Standings unavailable")
    }

    /// The page's status line: the session, its state, where and when (Expo's context status).
    static func contextLine(_ session: SportsRaceEvent, weekend: SportsRaceEvent) -> String {
        [session.sessionType, sessionState(session), session.place(weekend), date(session.start)].compactMap { $0 }
            .joined(separator: " · ")
    }

    /// A session in the session picker: "FP1 · Results · Sep 4, 10:30 AM".
    static func sessionOption(_ session: SportsRaceEvent) -> String {
        "\(session.sessionType ?? String(localized: "Session")) · \(sessionState(session)) · \(date(session.start))"
    }

    /// What the stream picker searches for and the player shows (Expo `raceWatchTarget` title).
    static func watchTitle(_ weekend: SportsRaceEvent, _ session: SportsRaceEvent) -> String {
        "\(weekend.title.trimmingCharacters(in: .whitespaces)) · \(session.sessionType ?? session.title)"
    }

    /// The line over a session's results: what the snapshot is, whether updates are late and
    /// when it was taken, never implying tick-by-tick telemetry (Expo `raceUpdateLabel`).
    static func updateLabel(_ session: SportsRaceEvent, delayed: Bool) -> String {
        let what = if session.f1Archive?.recorded == true { String(localized: "Recorded snapshot") }
            else if session.isLive { String(localized: "Live session · Periodic updates") }
            else { sessionState(session) }
        let when = session.updated.map { String(localized: "Snapshot updated \(date($0))") }
            ?? String(localized: "Update time unavailable")
        return [what, delayed ? String(localized: "Updates delayed") : nil, when].compactMap { $0 }.joined(separator: " · ")
    }

    /// Where a session's figures come from and when they were checked.
    static func sourceLine(_ session: SportsRaceEvent) -> String {
        let source = if session.f1Archive != nil { String(localized: "F1 timing archive") }
            else if session.riders { String(localized: "MotoGP official results") }
            else { "ESPN" }
        return "\(source) · \(checked(session.updated))"
    }

    /// "Checked Oct 23, 10:20 AM", or "Update time unavailable".
    static func checked(_ date: Date?) -> String {
        date.map { String(localized: "Checked \(Self.date($0))") } ?? String(localized: "Update time unavailable")
    }

    /// What a session with no entries says, as title and message (Expo `emptySessionNotice`).
    static func emptyNotice(_ session: SportsRaceEvent) -> (title: String, message: String) {
        let label = session.sessionType ?? String(localized: "Session")
        switch sessionState(session) {
        case String(localized: "Cancelled"):
            return (String(localized: "\(label) cancelled"),
                    String(localized: "The provider reports this session as cancelled. No classification has been supplied."))
        case String(localized: "Postponed"):
            return (String(localized: "\(label) postponed"),
                    String(localized: "The provider reports this session as postponed. The listed time may change; no classification has been supplied."))
        case String(localized: "Scheduled"):
            return (String(localized: "\(label) scheduled"),
                    String(localized: "Session entries have not been supplied yet. Results will appear here when reported by the provider."))
        case String(localized: "Results"):
            return (String(localized: "\(label) results unavailable"),
                    String(localized: "The session is marked complete, but the provider has not supplied a classification."))
        default:
            return (String(localized: "\(label) classification unavailable"),
                    String(localized: "The session is marked live, but the provider has not supplied positions or entries. Live timing is unavailable."))
        }
    }

    /// "Sep 6, 1:00 PM" (Expo `raceDate`).
    static func date(_ date: Date?) -> String {
        guard let date else { return String(localized: "Date unavailable") }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "1:00 PM".
    static func time(_ date: Date?) -> String {
        date?.formatted(date: .omitted, time: .shortened) ?? String(localized: "Time TBD")
    }

    /// "5.793 km".
    static func kilometres(_ metres: Int) -> String { String(format: "%.3f km", Double(metres) / 1000) }

    private static let smallWords: Set = ["of", "the", "and", "de", "del"]
    private static let acronyms: Set = ["usa", "uk", "tt", "gp", "f1"]

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
