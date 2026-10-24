import Foundation

/// `GET /api/sports/status`: whether the hub is on and whether the server answers per-day
/// scoreboards (`dateQueries`).
struct SportsStatus: Decodable {
    let enabled: Bool
    let dateQueries: Bool?
    let lastRefresh: String?
    let lastError: String?
}

/// A league of `GET /api/sports/leagues`. Only enabled leagues with a working schedule show.
struct SportsLeague: Decodable, Identifiable, Hashable {
    let id: String
    let enabled: Bool
    let name: String?
    let sport: String?
    /// The Expo catalog's sport family ("american-football", "ice-hockey", "rugby-union"…).
    let applicationSport: String?
    let college: Bool?
    let adapter: String?
    let eventKind: String?
    let supportsTeams: Bool?
    let coverageNote: String?
    let implementationStatus: String?
    let capabilities: [String]?

    var label: String { name ?? id.uppercased() }

    /// As the Expo catalog: enabled, validated or limited, and able to list a schedule. Older
    /// servers send neither field, and every enabled league counts.
    var isUsable: Bool {
        guard enabled else { return false }
        if let status = implementationStatus, status != "validated", status != "limited" { return false }
        if let capabilities, !capabilities.contains("schedule") { return false }
        return true
    }

    /// The id a followed competition is saved under in the profile's sports preferences,
    /// shared with the Expo app (`sports-follows.ts`).
    var followID: String { Self.followAliases[id] ?? id }

    static let followAliases: [String: String] = [
        "soccer-eng.1": "premier-league", "soccer-esp.1": "la-liga", "soccer-ger.1": "bundesliga",
        "soccer-ita.1": "serie-a", "soccer-fra.1": "ligue-1", "soccer-usa.1": "mls", "soccer-usa.nwsl": "nwsl",
        "soccer-uefa.champions": "uefa-champions-league", "college-football": "ncaa-football",
        "mens-college-basketball": "ncaa-mens-basketball", "womens-college-basketball": "ncaa-womens-basketball",
        "f1": "formula-one", "nascar": "nascar-cup",
    ]
}

struct SportsLeaguesResponse: Decodable {
    let leagues: LossyArray<SportsLeague>
}

/// `GET /api/sports/scoreboard[?date=]`. A dated board also says when it was built and whether it,
/// or any league on it, is serving older data (Expo's "Updates delayed" on a card).
struct SportsScoreboard: Decodable {
    var games: [SportsGame] = []
    var updatedAt: String?
    var stale = false
    var leagues: [SportsLeagueFreshness] = []

    private enum CodingKeys: String, CodingKey { case games, updatedAt, stale, leagues }

    init(games: [SportsGame] = [], updatedAt: String? = nil, stale: Bool = false, leagues: [SportsLeagueFreshness] = []) {
        self.games = games
        self.updatedAt = updatedAt
        self.stale = stale
        self.leagues = leagues
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        games = try c.decodeLossyArray(SportsGame.self, forKey: .games)
        updatedAt = c.sportsValue(String.self, .updatedAt)
        stale = c.sportsValue(Bool.self, .stale) ?? false
        leagues = c.sportsList(SportsLeagueFreshness.self, .leagues)
    }

    /// The leagues whose cards say "Updates delayed": every one on a board the server marks stale
    /// (only a board that says when it was built), else those its `leagues` mark stale.
    var staleLeagues: Set<String> {
        if updatedAt != nil, stale { return Set(games.map(\.league)) }
        return Set(leagues.filter(\.stale).map(\.league))
    }
}

/// A game, match, bout card or tournament day. Equal only when every field is (a refresh
/// that brings new plays redraws the page); hashed by id.
struct SportsGame: Decodable, Identifiable, Hashable {
    let id: String
    let league: String
    let sport: String?
    let title: String?
    let eventKind: String?
    /// The tournament, draw and round of a tennis match ("US Open · Men's Singles · …").
    let eventContext: String?
    let courtName: String?
    /// Sets in a tennis match (3 or 5).
    let bestOf: Int?
    let neutralSite: Bool?
    let startTime: String
    let endTime: String?
    let status: String
    let statusDetail: String?
    let period: String?
    let clock: String?
    let venue: String?
    let broadcasts: [String]?
    var homeTeam: SportsTeam
    var awayTeam: SportsTeam
    let combat: SportsCombat?
    /// The players, fighters or teams listed for the event (golf's field with scores).
    let participants: SportsParticipants?
    /// NFL and college football's down, distance and possession while live.
    let footballSituation: SportsFootballSituation?
    /// MLB's at-bat while live (the scoreboard's; the page prefers `detail.sport`).
    let liveSituation: SportsBaseballSituation?
    let detail: SportsGameDetail?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var start: Date { Self.date(startTime) ?? .distantPast }
    /// Multi-day events (golf, cricket, a fight card) carry an end; Go's zero time means none.
    var end: Date? { endTime.flatMap(Self.date).flatMap { $0 > start ? $0 : nil } }

    var lifecycle: SportsLifecycle { SportsLifecycle(status: status, detail: statusDetail) }

    /// A matchup of two named sides; other events (golf, a fight card) show their title.
    var isMatchup: Bool { !homeTeam.name.isEmpty && !awayTeam.name.isEmpty && combat == nil }

    var displayTitle: String {
        if let card = combat?.cardName, !card.isEmpty { return card }
        if let title, !title.isEmpty { return title }
        return "\(awayTeam.name) at \(homeTeam.name)"
    }

    /// Scores only once the game is under way, as the Expo normaliser keeps them.
    var showsScore: Bool { isMatchup && lifecycle != .scheduled && (homeTeam.score != nil || awayTeam.score != nil) }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return [displayTitle, homeTeam.name, awayTeam.name, homeTeam.abbreviation ?? "", awayTeam.abbreviation ?? "", league]
            .contains { $0.lowercased().contains(q) }
    }

    static func date(_ text: String) -> Date? {
        if let d = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        guard let d = try? Date(text, strategy: .iso8601), d.timeIntervalSince1970 > 0 else { return nil }
        return d
    }
}

struct SportsTeam: Decodable, Hashable {
    let id: String
    let name: String
    let location: String?
    let nickname: String?
    let abbreviation: String?
    let logoUrl: String?
    /// Hex without '#'.
    let color: String?
    let alternateColor: String?
    let score: String?
    /// Penalty shootout goals (soccer).
    let shootoutScore: Int?
    let winner: Bool?
    var record: String?
    let conferenceRecord: String?
    let standingSummary: String?
    let rank: Int?
    let seed: Int?

    var logo: URL? { logoUrl.flatMap { $0.hasPrefix("https://") ? URL(string: $0) : nil } }
    var shortName: String { abbreviation.flatMap { $0.isEmpty ? nil : $0 } ?? name }
    /// A poll ranking worth showing (Expo keeps 1–25).
    var displayRank: Int? { rank.flatMap { (1...25).contains($0) ? $0 : nil } }
    /// A tournament seed (Expo keeps 1–128).
    var displaySeed: Int? { seed.flatMap { (1...128).contains($0) ? $0 : nil } }
}

/// The hub's lifecycle for a game; delays and postponements come from the status text.
enum SportsLifecycle: Equatable {
    case scheduled, live, final, delayed, postponed, canceled

    init(status: String, detail: String?) {
        let text = (detail ?? "").lowercased()
        if text.contains("postpon") { self = .postponed }
        else if text.contains("cancel") { self = .canceled }
        else if text.contains("delay") || text.contains("suspend") { self = .delayed }
        else if status == "live" { self = .live }
        else if status == "final" { self = .final }
        else { self = .scheduled }
    }

    var pill: String {
        switch self {
        case .scheduled: String(localized: "UPCOMING")
        case .live: String(localized: "LIVE")
        case .final: String(localized: "FINAL")
        case .delayed: String(localized: "DELAYED")
        case .postponed: String(localized: "POSTPONED")
        case .canceled: String(localized: "CANCELED")
        }
    }

    var isScheduleChange: Bool { self == .delayed || self == .postponed || self == .canceled }
}

// MARK: Streams

/// `GET /api/sports/game/{id}/streams`: live channels that look like they carry the game.
struct SportsStreamsResponse: Decodable {
    let groups: LossyArray<SportsStreamGroup>?
}

struct SportsStreamGroup: Decodable {
    let confidenceTier: String
    let primary: SportsStreamMatch
    let alternatives: [SportsStreamMatch]?
}

struct SportsStreamMatch: Decodable, Identifiable, Hashable {
    let channelId: String
    let channelName: String
    let channelUrl: String
    let channelLogo: String?
    let channelTvgId: String?
    let sourceId: String?
    let sourceName: String?
    let programTitle: String?
    let confidence: Double?
    let confidenceTier: String?
    let matchReason: String?

    var id: String { "\(channelId)|\(channelUrl)" }
    var isStrong: Bool { confidenceTier == "strong" }

    /// The channel as Live TV tunes it.
    var channel: LiveChannel {
        LiveChannel(id: channelId, name: channelName, url: channelUrl, logo: channelLogo, group: nil,
                    tvgId: channelTvgId, tvgName: nil, sourceId: sourceId, sourceName: sourceName, playbackId: nil)
    }
}

// MARK: Preferences

/// `GET/PUT /api/users/{id}/sports/preferences`, shared with the Expo app. The PUT sends the
/// revision it read; the server answers 409 when another device saved in between.
struct SportsPreferencesEnvelope: Codable {
    var revision: Int
    var preferences: SportsPreferences
}

struct SportsPreferences: Codable, Equatable {
    var version = 1
    var pinnedSportIds: [String] = []
    var competitionIds: [String] = []
    var teamIds: [String] = []
    var athleteIds: [String] = []
    /// Kept as sent: the TV apps don't edit school follows.
    var schools: [SportsSchoolFollow] = []
}

struct SportsSchoolFollow: Codable, Equatable {
    let schoolId: String
    let scope: String
    let programIds: [String]?
}
