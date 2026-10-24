import Foundation

/// `GET /api/sports/standings/{league}` (Expo `LeagueStandings`): the provider's season tables, one
/// per conference, division or league table. `state` is `available`, `stale` or `unavailable`
/// (with a `reason`); a stale answer keeps the last tables. (The game page's own standings are
/// `SportsStandingGroup`.)
struct SportsLeagueStandings: Decodable, Hashable {
    var league = ""
    var state = "unavailable"
    var source = ""
    var sourceUrl = ""
    var updatedAt: String?
    var reason: String?
    var groups: [SportsLeagueTable] = []

    private enum CodingKeys: String, CodingKey { case league, state, source, sourceUrl, updatedAt, reason, groups }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        league = c.sportsValue(String.self, .league) ?? ""
        state = c.sportsValue(String.self, .state) ?? "unavailable"
        source = c.sportsValue(String.self, .source) ?? ""
        sourceUrl = c.sportsValue(String.self, .sourceUrl) ?? ""
        updatedAt = c.sportsValue(String.self, .updatedAt)
        reason = c.sportsValue(String.self, .reason)
        groups = c.sportsList(SportsLeagueTable.self, .groups)
    }

    var available: Bool { state == "available" }
    var delayed: Bool { state == "stale" || state == "unavailable" }
}

/// One table: its columns in the provider's order and its rows, leader first.
struct SportsLeagueTable: Decodable, Identifiable, Hashable {
    var id: String
    var title = ""
    var season = 0
    var seasonLabel = ""
    var columns: [SportsTableColumn] = []
    var rows: [SportsTableRow] = []

    private enum CodingKeys: String, CodingKey { case id, title, season, seasonLabel, columns, rows }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.sportsValue(String.self, .title) ?? ""
        season = c.sportsValue(Int.self, .season) ?? 0
        seasonLabel = c.sportsValue(String.self, .seasonLabel) ?? ""
        columns = c.sportsList(SportsTableColumn.self, .columns)
        rows = c.sportsList(SportsTableRow.self, .rows)
    }
}

/// A statistic of the table: `key` (`overall`, `playoffSeed`, `vs. Conf.`…) and its heading.
struct SportsTableColumn: Decodable, Hashable {
    let key: String
    var label = ""

    private enum CodingKeys: String, CodingKey { case key, label }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = c.sportsValue(String.self, .label) ?? ""
    }
}

/// A team's (or an athlete's) line: its values by column key, as display text.
struct SportsTableRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    var abbreviation: String?
    var kind = "team"
    var values: [String: String] = [:]

    private enum CodingKeys: String, CodingKey { case id, name, abbreviation, kind, values }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        abbreviation = c.sportsValue(String.self, .abbreviation)
        kind = c.sportsValue(String.self, .kind) ?? "team"
        values = c.sportsValue([String: String].self, .values) ?? [:]
    }
}

/// League standings rules (Expo `SportsLeagueStandings` and `sports-hub-records.ts`): the columns
/// a table shows, the leading entry, and records for hub cards that lack one.
enum SportsStandings {
    /// The columns a table shows, at most `limit`, in Expo's order per kind of league: soccer
    /// rank, points, played, goal difference, record; college record, conference, rank, seed;
    /// the rest rank, seed, record, points, win %, games behind.
    static func columns(_ league: String, _ table: SportsLeagueTable, limit: Int = 4) -> [SportsTableColumn] {
        let order: [String] = if league.hasPrefix("soccer-") {
            ["rank", "points", "gamesPlayed", "pointDifferential", "overall"]
        } else if league.contains("college") {
            ["overall", "vs. Conf.", "rank", "playoffSeed", "winPercent"]
        } else {
            ["rank", "playoffSeed", "overall", "championshipPts", "points", "winPercent", "gamesBehind"]
        }
        return Array(order.compactMap { key in table.columns.first { $0.key == key } }.prefix(limit))
    }

    /// A value as shown: a rank or seed of 0 means none; a missing value is a dash.
    static func value(_ row: SportsTableRow, _ key: String) -> String {
        let value = row.values[key]
        if (key == "rank" || key == "playoffSeed") && value == "0" { return "–" }
        return value ?? "–"
    }

    /// The table's leader: rank 1, else seed 1.
    static func leader(_ table: SportsLeagueTable) -> SportsTableRow? {
        table.rows.first { $0.values["rank"] == "1" || $0.values["playoffSeed"] == "1" }
    }

    /// "LEADING ENTRY · RANK 1" or "… SEED 1".
    static func leaderEyebrow(_ row: SportsTableRow) -> String {
        row.values["rank"] == "1" ? String(localized: "LEADING ENTRY · RANK 1") : String(localized: "LEADING ENTRY · SEED 1")
    }

    /// "41 points · 12-3 record": championship points, else table points, and the record.
    static func leaderSummary(_ row: SportsTableRow, _ table: SportsLeagueTable) -> String {
        let points = row.values["championshipPts"]
            ?? (table.columns.contains { $0.key == "points" } ? row.values["points"] : nil)
        return [points.map { String(localized: "\($0) points") }, row.values["overall"].map { String(localized: "\($0) record") }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The group picker's name: college tables are conferences.
    static func groupLabel(_ league: String) -> String {
        league.contains("college") ? String(localized: "Conference") : String(localized: "Table")
    }

    /// A season record for a hub card's side that has none (Expo `participantWithStanding`): the
    /// table row of the same team id (a provider-prefixed id matches on its last part), its
    /// `overall`, else wins–losses[–ties] when they are whole numbers. Table position is never used.
    static func record(_ team: SportsTeam, _ tables: [SportsLeagueTable]) -> String? {
        guard team.record?.isEmpty ?? true, !team.id.isEmpty else { return nil }
        let id = team.id.split(separator: ":").last.map(String.init) ?? team.id
        guard let row = tables.lazy.flatMap(\.rows).first(where: { $0.kind == "team" && ($0.id == team.id || $0.id == id) })
        else { return nil }
        if let overall = row.values["overall"]?.trimmingCharacters(in: .whitespaces), !overall.isEmpty { return overall }
        let whole = { (key: String) in row.values[key].flatMap { $0.wholeMatch(of: /\d+/) != nil ? $0 : nil } }
        guard let wins = whole("wins"), let losses = whole("losses") else { return nil }
        return [wins, losses, whole("ties")].compactMap { $0 }.joined(separator: "–")
    }

    /// The game with each side's record filled from `tables` where the scoreboard sent none.
    static func withRecords(_ game: SportsGame, _ tables: [SportsLeagueTable]) -> SportsGame {
        let away = record(game.awayTeam, tables), home = record(game.homeTeam, tables)
        guard away != nil || home != nil else { return game }
        var filled = game
        if let away { filled.awayTeam.record = away }
        if let home { filled.homeTeam.record = home }
        return filled
    }
}
