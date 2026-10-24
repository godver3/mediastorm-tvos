import Foundation

/// `GET /api/sports/cycling` (Expo `CyclingFeed`, a `ModuleState<CyclingRace[]>`): the organizers'
/// race calendars with each race's stages, and every organizer's feed state in `coverage`.
/// `state` is `available`, `stale`, `unavailable`, `pending` or `unsupported`; only the first two
/// carry races. Lists are lenient: a bad item is skipped and `null` is empty.
struct SportsCyclingFeed: Decodable, Hashable {
    var state = "unavailable"
    var source: SportsCyclingEvidence?
    var data: [SportsCyclingRace] = []
    var reason: String?
    var coverage: [SportsCyclingCoverage] = []

    private enum CodingKeys: String, CodingKey { case state, source, data, reason, coverage }

    init(state: String = "available", data: [SportsCyclingRace] = [], coverage: [SportsCyclingCoverage] = []) {
        self.state = state
        self.data = data
        self.coverage = coverage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.sportsValue(String.self, .state) ?? "unavailable"
        source = c.sportsValue(SportsCyclingEvidence.self, .source)
        data = c.sportsList(SportsCyclingRace.self, .data)
        reason = c.sportsValue(String.self, .reason)
        coverage = c.sportsList(SportsCyclingCoverage.self, .coverage)
    }

    /// The races, when the feed has any to show.
    var races: [SportsCyclingRace] { state == "available" || state == "stale" ? data : [] }

    /// Updates are late or missing (Expo's "Cycling updates delayed or unavailable").
    var delayed: Bool { state == "stale" || state == "unavailable" }
}

/// Where a cycling answer came from and when it was read (Expo `SourceEvidence`).
struct SportsCyclingEvidence: Decodable, Hashable {
    var provider = ""
    var observedAt: String?
    var updatedAt: String?

    private enum CodingKeys: String, CodingKey { case provider, observedAt, updatedAt }

    init(provider: String = "", observedAt: String? = nil, updatedAt: String? = nil) {
        self.provider = provider
        self.observedAt = observedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = c.sportsValue(String.self, .provider) ?? ""
        observedAt = c.sportsValue(String.self, .observedAt)
        updatedAt = c.sportsValue(String.self, .updatedAt)
    }
}

/// One organizer's feed state.
struct SportsCyclingCoverage: Decodable, Hashable {
    var id = ""
    var name = ""
    var state = "available"

    private enum CodingKeys: String, CodingKey { case id, name, state }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.sportsValue(String.self, .id) ?? ""
        name = c.sportsValue(String.self, .name) ?? ""
        state = c.sportsValue(String.self, .state) ?? "available"
    }
}

/// A race of an organizer's calendar (Expo `CyclingRace`): a stage race, a one-day race or a
/// championship, with its stages. Dates are `YYYY-MM-DD` with no time of day. `scheduleOnly`
/// races have dates only (no results to load); `calendarOnly` ones come from a calendar listing.
struct SportsCyclingRace: Decodable, Identifiable, Hashable {
    var id: String
    var name = ""
    var category = "unknown"
    var raceKind: String?
    var calendarOnly = false
    var scheduleOnly = false
    var country: String?
    var classification: String?
    var restDays: [String] = []
    var startDate: String?
    var endDate: String?
    var stages: [SportsCyclingStage] = []
    var source = SportsCyclingEvidence()
    var sourceUrl: String?
    /// Recorded results rather than a live organizer feed.
    var captured = false

    private enum CodingKeys: String, CodingKey {
        case id, name, category, raceKind, calendarOnly, scheduleOnly, country, classification, restDays, startDate, endDate
        case stages, source, sourceUrl, captured
    }

    init(id: String, name: String = "", raceKind: String? = nil, startDate: String? = nil, endDate: String? = nil,
         stages: [SportsCyclingStage] = []) {
        self.id = id
        self.name = name
        self.raceKind = raceKind
        self.startDate = startDate
        self.endDate = endDate
        self.stages = stages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.sportsValue(String.self, .name) ?? ""
        category = c.sportsValue(String.self, .category) ?? "unknown"
        raceKind = c.sportsValue(String.self, .raceKind)
        calendarOnly = c.sportsValue(Bool.self, .calendarOnly) ?? false
        scheduleOnly = c.sportsValue(Bool.self, .scheduleOnly) ?? false
        country = c.sportsValue(String.self, .country)
        classification = c.sportsValue(String.self, .classification)
        restDays = c.sportsList(String.self, .restDays)
        startDate = c.sportsValue(String.self, .startDate)
        endDate = c.sportsValue(String.self, .endDate)
        stages = c.sportsList(SportsCyclingStage.self, .stages)
        source = c.sportsValue(SportsCyclingEvidence.self, .source) ?? SportsCyclingEvidence()
        sourceUrl = c.sportsValue(String.self, .sourceUrl)
        captured = c.sportsValue(Bool.self, .captured) ?? false
    }

    var oneDay: Bool { raceKind == "one-day" }
    var championship: Bool { raceKind == "championship" }

    /// The format Expo filters by: a missing kind counts as a stage race.
    var format: String { raceKind ?? "stage-race" }

    /// The id a followed race is saved under, the same across editions (Expo `cyclingFollowId`).
    var followID: String { SportsCycling.followID(id) }

    /// The last day of racing (a one-day race's start).
    var lastDate: String? { endDate.flatMap { $0.isEmpty ? nil : $0 } ?? startDate }
}

/// A stage (or a one-day race) of a race (Expo `CyclingStage`). The feed's copy carries results
/// only once a stage's own answer (`sportsCyclingStage`) has been asked for.
struct SportsCyclingStage: Decodable, Identifiable, Hashable {
    var id: String
    var name = ""
    var date: String?
    var departure: String?
    var arrival: String?
    var distance: String?
    var terrain: String?
    /// `scheduled`, `cancelled` or `unknown` (a held stage reports unknown).
    var status = "unknown"
    var results = SportsCyclingResults()
    var generalClassification = SportsCyclingResults()
    var generalClassificationLabel: String?
    /// A team time trial's classification by team.
    var teamResults: SportsCyclingResults?
    var routeGuide: SportsCyclingRouteGuide?

    private enum CodingKeys: String, CodingKey {
        case id, name, date, departure, arrival, distance, terrain, status, results, generalClassification
        case generalClassificationLabel, teamResults, routeGuide
    }

    init(id: String, name: String = "", date: String? = nil, status: String = "unknown",
         results: SportsCyclingResults = SportsCyclingResults()) {
        self.id = id
        self.name = name
        self.date = date
        self.status = status
        self.results = results
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.sportsValue(String.self, .name) ?? ""
        date = c.sportsValue(String.self, .date)
        departure = c.sportsValue(String.self, .departure)
        arrival = c.sportsValue(String.self, .arrival)
        distance = c.sportsValue(String.self, .distance)
        terrain = c.sportsValue(String.self, .terrain)
        status = c.sportsValue(String.self, .status) ?? "unknown"
        results = c.sportsValue(SportsCyclingResults.self, .results) ?? SportsCyclingResults()
        generalClassification = c.sportsValue(SportsCyclingResults.self, .generalClassification) ?? SportsCyclingResults()
        generalClassificationLabel = c.sportsValue(String.self, .generalClassificationLabel)
        teamResults = c.sportsValue(SportsCyclingResults.self, .teamResults)
        routeGuide = c.sportsValue(SportsCyclingRouteGuide.self, .routeGuide)
    }

    var cancelled: Bool { status == "cancelled" }

    /// "Thoiry → Paris Champs-Élysées".
    var route: String {
        [departure, arrival].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " → ")
    }

    /// Published finishers: the hub shows the stage as a result once they're in.
    var completed: Bool { !results.rows.isEmpty }
}

/// A classification of a stage (Expo `ModuleState<CyclingResult[]>`): its `state` and, when
/// `available` or `stale`, its entries.
struct SportsCyclingResults: Decodable, Hashable {
    var state = "pending"
    var source: SportsCyclingEvidence?
    var data: [SportsCyclingResult] = []
    var reason: String?

    private enum CodingKeys: String, CodingKey { case state, source, data, reason }

    init(state: String = "pending", data: [SportsCyclingResult] = []) {
        self.state = state
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.sportsValue(String.self, .state) ?? "pending"
        source = c.sportsValue(SportsCyclingEvidence.self, .source)
        data = c.sportsList(SportsCyclingResult.self, .data)
        reason = c.sportsValue(String.self, .reason)
    }

    var stale: Bool { state == "stale" }

    /// The entries, when the state carries any.
    var rows: [SportsCyclingResult] { state == "available" || state == "stale" ? data : [] }
}

/// A rider's (or, in a team classification, a team's) line: position, time and gap as the
/// organizer reported them, or a DNF / DNS / DSQ `result`.
struct SportsCyclingResult: Decodable, Identifiable, Hashable {
    var id: String
    var name = ""
    var team: String?
    var teamId: String?
    var bib: Int?
    var nationality: String?
    var rank: Int?
    var time: String?
    var gap: String?
    var result: String?

    private enum CodingKeys: String, CodingKey { case id, name, team, teamId, bib, nationality, rank, time, gap, result }

    init(id: String, name: String, rank: Int? = nil, time: String? = nil, gap: String? = nil, result: String? = nil) {
        self.id = id
        self.name = name
        self.rank = rank
        self.time = time
        self.gap = gap
        self.result = result
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = c.sportsValue(String.self, .name) ?? ""
        team = c.sportsValue(String.self, .team)
        teamId = c.sportsValue(String.self, .teamId)
        bib = c.sportsValue(Int.self, .bib)
        nationality = c.sportsValue(String.self, .nationality)
        rank = c.sportsValue(Int.self, .rank)
        time = c.sportsValue(String.self, .time)
        gap = c.sportsValue(String.self, .gap)
        result = c.sportsValue(String.self, .result)
    }
}

/// The organizer's stage guide: route map and profile images.
struct SportsCyclingRouteGuide: Decodable, Hashable {
    var state = "unavailable"
    var sourceUrl: String?
    var mapUrl: String?
    var profileUrl: String?
    var reason: String?

    private enum CodingKeys: String, CodingKey { case state, sourceUrl, mapUrl, profileUrl, reason }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.sportsValue(String.self, .state) ?? "unavailable"
        sourceUrl = c.sportsValue(String.self, .sourceUrl)
        mapUrl = c.sportsValue(String.self, .mapUrl)
        profileUrl = c.sportsValue(String.self, .profileUrl)
        reason = c.sportsValue(String.self, .reason)
    }
}
