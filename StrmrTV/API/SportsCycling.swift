import Foundation

/// The calendar's place for a race relative to today (Expo `CyclingCalendarPeriod`), in the
/// calendar's order.
enum SportsCyclingPeriod: Int, Comparable {
    case current, upcoming, past, undated

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// The calendar card's eyebrow ("CURRENT DATES · ").
    var eyebrow: String {
        switch self {
        case .current: String(localized: "CURRENT DATES · ")
        case .upcoming: String(localized: "UPCOMING · ")
        case .past: String(localized: "PAST DATES · ")
        case .undated: ""
        }
    }
}

/// A race on the Sports hub's day: one stage, or the race itself on a rest day (Expo `HubCard`
/// of kind `cycling`).
struct SportsCyclingListing: Hashable {
    let race: SportsCyclingRace
    let stage: SportsCyclingStage?
    let restDay: Bool
    /// The hub's day, `YYYY-MM-DD`.
    let day: String

    /// A stage with published finishers is a result; a cancelled one a schedule change; the rest upcoming.
    var lifecycle: SportsLifecycle {
        if stage?.completed == true { return .final }
        if stage?.cancelled == true { return .canceled }
        return .scheduled
    }

    var key: String { "cycling:\(stage?.id ?? race.id)" }

    /// The stage's day (no time of day), else the hub's day: the start of that local day, so
    /// cycling sorts first in Upcoming and last in Results.
    var start: Date { SportsCycling.dayStart(stage?.date ?? day) ?? .distantPast }

    /// The next stage after a rest day.
    var nextStage: SportsCyclingStage? {
        restDay ? race.stages.first { ($0.date ?? "") > day } : nil
    }
}

/// Road cycling's rules (Expo `sports-cycling.ts` and the hub's cycling cards): dates, the stage
/// a race opens on, rest days, the calendar's order, the hub's cards and following.
enum SportsCycling {
    static let sport = "cycling"

    /// A race followed across editions: `aso:tour:2026` → `aso:tour`.
    static func followID(_ raceID: String) -> String {
        raceID.replacingOccurrences(of: #":\d{4}$"#, with: "", options: .regularExpression)
    }

    /// The stage endpoint's segments from `org:race:year:number`.
    static func stagePath(_ stageID: String) -> (race: String, year: String, number: String)? {
        let parts = stageID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4, !parts[1...3].contains(where: \.isEmpty) else { return nil }
        return (parts[1], parts[2], parts[3])
    }

    /// A `YYYY-MM-DD` date as a local calendar day (never midnight UTC).
    static func day(_ text: String?) -> DateComponents? {
        guard let text, text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = Calendar.current.date(from: components),
              Calendar.current.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return components
    }

    /// Today (or `offset` days away) in the device's zone, as cycling dates are written.
    static func today(offset: Int = 0, now: Date = Date()) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: now) ?? now
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dayStart(_ text: String) -> Date? { day(text).flatMap { Calendar.current.date(from: $0) } }

    /// "Jul 26, 2026"; a date without a time is never turned into midnight; unknown → "Date to be confirmed".
    static func date(_ text: String?, locale: Locale = .current) -> String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day().year().locale(locale)
        if let start = text.flatMap(dayStart) { return start.formatted(style) }
        if let text, let instant = SportsGame.date(text) { return instant.formatted(style) }
        return String(localized: "Date to be confirmed")
    }

    /// "Jul 4, 2026 – Jul 26, 2026", one date for a one-day race.
    static func dateRange(_ race: SportsCyclingRace) -> String {
        guard let end = race.endDate, end != race.startDate else { return date(race.startDate) }
        return "\(date(race.startDate)) – \(date(end))"
    }

    /// The latest dated stage on or before `today` (finished or not), else the first (Expo `defaultCyclingStage`).
    static func defaultStage(_ race: SportsCyclingRace, today: String = today()) -> SportsCyclingStage? {
        race.stages.last { ($0.date.map { $0 <= today }) ?? false } ?? race.stages.first
    }

    /// Where a race sits in the calendar: under way, still to come, over, or without usable dates.
    static func period(_ race: SportsCyclingRace, today: String = today()) -> SportsCyclingPeriod {
        guard let start = race.startDate, day(start) != nil else { return .undated }
        let end = race.endDate.flatMap { $0.isEmpty ? nil : $0 }
        if let end, day(end) == nil || end < start { return .undated }
        if start > today { return .upcoming }
        return (end ?? start) < today ? .past : .current
    }

    /// The calendar's order (Expo `compareCyclingCalendar`): current races, upcoming, past (most
    /// recent first), undated; then by start date, then name.
    static func calendarOrder(_ a: SportsCyclingRace, _ b: SportsCyclingRace, today: String = today()) -> Bool {
        let first = period(a, today: today), second = period(b, today: today)
        if first != second { return first < second }
        if first == .past, a.lastDate != b.lastDate { return (a.lastDate ?? "") > (b.lastDate ?? "") }
        if first != .past, a.startDate != b.startDate { return (a.startDate ?? "") < (b.startDate ?? "") }
        return a.name < b.name
    }

    /// A race's entries for `day` (Expo `cyclingDayEntries`): a calendar listing within its dates,
    /// else every stage on the day, else one entry without a stage, a rest day when the race says so.
    static func dayEntries(_ race: SportsCyclingRace, day: String) -> [(stage: SportsCyclingStage?, restDay: Bool)] {
        if race.calendarOnly, let start = race.startDate, day >= start, day <= (race.lastDate ?? start) {
            return [(race.stages.first, false)]
        }
        let stages = race.stages.filter { $0.date == day }
        if !stages.isEmpty { return stages.map { ($0, false) } }
        return [(nil, race.restDays.contains(day))]
    }

    /// The hub's cycling cards for `day`: every race running that day that `include` keeps.
    static func listings(_ races: [SportsCyclingRace], day: String,
                         include: (SportsCyclingRace) -> Bool = { _ in true }) -> [SportsCyclingListing] {
        races.filter { race in
            guard let start = race.startDate, !start.isEmpty else { return false }
            return start <= day && (race.lastDate ?? start) >= day && include(race)
        }
        .flatMap { race in
            dayEntries(race, day: day).map { SportsCyclingListing(race: race, stage: $0.stage, restDay: $0.restDay, day: day) }
        }
    }

    /// Whether Find Streams can search for a stage (Expo `cyclingWatchTarget.canSearch`): not a
    /// recorded capture, not cancelled, dated, and today or later (a calendar listing until it ends).
    static func canSearch(_ race: SportsCyclingRace, _ stage: SportsCyclingStage?, today: String = today()) -> Bool {
        guard let stage, let date = stage.date, !race.captured, !stage.cancelled else { return false }
        return date >= today || (race.calendarOnly && (race.endDate ?? "") >= today)
    }

    /// Following shows a race followed by itself or through cycling as a pinned sport.
    static func isFollowed(_ race: SportsCyclingRace, competitions: [String], pinned: [String]) -> Bool {
        competitions.contains(race.followID) || pinned.contains(sport)
    }

    /// Where a cycling card sorts in its row: followed races in follow order, then cycling as a pinned sport.
    static func followRank(_ race: SportsCyclingRace, competitions: [String], pinned: [String]) -> Int {
        if let followed = competitions.firstIndex(of: race.followID) { return followed }
        if let pin = pinned.firstIndex(of: sport) { return competitions.count + pin }
        return Int.max
    }
}
