import Foundation

/// The Sports hub's events for one day, a port of the Expo TV hub's data flow: `status`,
/// `leagues` and the day's scoreboard(s), refreshed every 30 s while anything is live, 60 s for
/// the rest of today, 5 min for other days; the race board, polled on its own cadence
/// (`SportsRaceHub.refreshSeconds`) while a racing series is on (Expo `useSportsHubRaces`); the
/// cycling calendar every 5 min while cycling is on; and league tables for the records cards
/// lack (Expo `useSportsHubRecords`). `sport` and `league` narrow the rows (Expo's Sport and
/// League filters, `SportsHubStore+Filters`).
@MainActor
final class SportsHubStore: ObservableObject {
    @Published private(set) var games: [SportsGame] = []
    @Published private(set) var leagues: [String: SportsLeague] = [:]
    /// The league catalog in the server's order (the League filter's order among equals).
    @Published private(set) var catalog: [SportsLeague] = []
    @Published private(set) var loading = true
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var dated = false
    /// Leagues whose scoreboard is serving older data (their cards say "Updates delayed").
    @Published private(set) var staleLeagues: Set<String> = []
    @Published var day: SportsDay = .today {
        didSet {
            guard day != oldValue else { return }
            ordering.reset()
            Task { await load() }
        }
    }
    @Published var filter: SportsFilter = .all
    @Published var followingOnly = false
    /// The Sport filter: a `SportsHubFilters.sports` id, or `SportsHubFilters.all`.
    @Published private(set) var sport = SportsHubFilters.all
    /// The League filter: a catalog league id, a cycling race's follow id, or `SportsHubFilters.all`.
    @Published var league = SportsHubFilters.all
    @Published var preferences: SportsPreferencesEnvelope?
    /// The race board's last answer, kept through failed reloads.
    @Published private(set) var raceBoard: SportsRaceBoard?
    @Published private(set) var raceFailed = false
    /// Bumped by Try Again: the race board and cycling loops restart at once.
    @Published private(set) var raceRetries = 0
    /// When the race board is next due: leaving the tab and coming back waits out the rest.
    private var raceDueAt = Date.distantPast
    /// The cycling calendar's last answer, kept through failed reloads.
    @Published private(set) var cyclingFeed: SportsCyclingFeed?
    @Published private(set) var cyclingFailed = false
    private var cyclingDueAt = Date.distantPast
    /// League tables by league, for the records cards lack; only available answers are kept.
    @Published private(set) var tables: [String: [SportsLeagueTable]] = [:]
    private var tablesAsked: Set<String> = []

    private let api = APIClient.shared
    private var loadID = 0
    /// Where each of the day's games sits in its row, kept across refreshes.
    var ordering = SportsHubOrdering()

    /// Followed competitions, in the order they were followed.
    var followed: [String] { preferences?.preferences.competitionIds ?? [] }

    var pinned: [String] { preferences?.preferences.pinnedSportIds ?? [] }

    /// Picks a sport; the league goes back to all of them.
    func chooseSport(_ id: String) {
        sport = id
        league = SportsHubFilters.all
    }

    func clearFilters() { chooseSport(SportsHubFilters.all) }

    func leagueName(_ id: String) -> String { leagues[id]?.label ?? SportsRaceFormat.seriesNames[id] ?? id.uppercased() }

    /// The catalog has a racing series turned on, so the race board is worth asking for.
    var racingEnabled: Bool { leagues.values.contains { $0.isUsable && $0.isRacing } }

    /// Racing is on but its board hasn't answered yet.
    var racesPending: Bool { racingEnabled && raceBoard == nil && !raceFailed }

    /// The race board failed or a series is stale or unavailable (Expo's hub issue line).
    var racingDelayed: Bool { racingEnabled && (raceFailed || raceBoard?.delayed == true) }

    /// The catalog has a cycling race turned on (Expo `sportEnabled('cycling')`).
    var cyclingEnabled: Bool { leagues.values.contains { $0.isUsable && SportsHubFilters.family($0) == SportsCycling.sport } }

    var cyclingPending: Bool { cyclingEnabled && cyclingFeed == nil && !cyclingFailed }

    /// Expo's "Cycling updates delayed or unavailable".
    var cyclingDelayed: Bool { cyclingEnabled && (cyclingFailed || cyclingFeed?.delayed == true) }

    /// The day's race sessions, one card per weekend in each lifecycle.
    var raceItems: [SportsHubItem] {
        guard let raceBoard else { return [] }
        return SportsRaceHub.listings(raceBoard, in: day.interval) { self.leagues[$0]?.isUsable == true }.map(SportsHubItem.race)
    }

    /// The day's cycling cards: each stage that day, or the race on a rest day.
    var cyclingItems: [SportsHubItem] {
        guard cyclingEnabled else { return [] }
        return SportsCycling.listings(cyclingFeed?.races ?? [], day: SportsCycling.today(offset: day.rawValue))
            .map(SportsHubItem.cycling)
    }

    /// The game's sport family (which side its card lists first).
    func kind(_ game: SportsGame) -> SportsKind { SportsKind(league: leagues[game.league], game: game) }

    var usableLeagues: [SportsLeague] {
        leagues.values.filter(\.isUsable).sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// The game with records from the league's table where the scoreboard sent none.
    func withRecord(_ game: SportsGame) -> SportsGame {
        tables[game.league].map { SportsStandings.withRecords(game, $0) } ?? game
    }

    var hasLive: Bool { games.contains { $0.lifecycle == .live } }

    func load() async {
        loadID += 1
        let id = loadID
        do {
            let current = try await api.sportsStatus()
            guard current.enabled else { throw APIError.notReady(String(localized: "Sports is turned off on this server.")) }
            let catalog = self.catalog.isEmpty ? try await api.sportsLeagues() : self.catalog
            let dates: [String?] = current.dateQueries == true ? day.scoreboardDates : [nil]
            // At most two days, fetched side by side (no task group: Swift 6.4 -O miscompiles
            // them, see HomeStore).
            async let first = api.sportsScoreboard(date: dates[0])
            async let second = dates.count > 1 ? api.sportsScoreboard(date: dates[1]) : SportsScoreboard()
            let boards = try await [first, second]
            var merged: [String: SportsGame] = [:]
            for game in boards.flatMap(\.games) { merged[game.id] = game }
            guard id == loadID else { return }
            self.catalog = catalog
            leagues = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            dated = current.dateQueries == true
            staleLeagues = boards.reduce(into: Set<String>()) { $0.formUnion($1.staleLeagues) }
            let shown = merged.values.filter(onDay)
            ordering.record(shown)
            games = shown
            ordering.record(raceItems)
            updatedAt = Date()
            error = nil
        } catch {
            guard id == loadID, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// Games starting on the day, events spanning it, and (today) anything still live.
    private func onDay(_ game: SportsGame) -> Bool {
        let interval = day.interval
        if interval.contains(game.start) { return true }
        if let end = game.end, game.start < interval.end, end > interval.start { return true }
        return day == .today && game.lifecycle == .live
    }

    /// Reloads the race board whenever it is due, for as long as the hub shows: every 30 s while
    /// a session is live, a series is delayed or the board is empty, else every 60 s; 30 s after
    /// a failure, keeping the last good board (Expo `useSportsHubRaces`).
    func pollRaces() async {
        while !Task.isCancelled {
            let wait = raceDueAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            do {
                let board = try await api.sportsRaces()
                raceBoard = board
                raceFailed = false
                ordering.record(raceItems)
                raceDueAt = Date().addingTimeInterval(TimeInterval(SportsRaceHub.refreshSeconds(board)))
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                raceFailed = true
                raceDueAt = Date().addingTimeInterval(TimeInterval(SportsRaceHub.retrySeconds))
            }
        }
    }

    /// Try Again: the scoreboard now, and the race board and cycling calendar without waiting.
    func retry() async {
        raceDueAt = .distantPast
        cyclingDueAt = .distantPast
        raceRetries += 1
        await load()
    }

    /// Reloads the cycling calendar every 5 min while the hub shows (Expo's hub cycling source),
    /// 30 s after a failure, keeping the last good answer.
    func pollCycling() async {
        while !Task.isCancelled {
            let wait = cyclingDueAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            do {
                cyclingFeed = try await api.sportsCycling()
                cyclingFailed = false
                ordering.record(cyclingItems)
                cyclingDueAt = Date().addingTimeInterval(300)
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                cyclingFailed = true
                cyclingDueAt = Date().addingTimeInterval(30)
            }
        }
    }

    /// The leagues whose games lack a side's record (the records task's key).
    var recordLeagues: [String] {
        Set(games.filter { ($0.awayTeam.record ?? "").isEmpty || ($0.homeTeam.record ?? "").isEmpty }.map(\.league)).sorted()
    }

    /// Fetches the tables of the leagues whose games lack a record, two at a time, once per league
    /// for the hub's life (Expo `useSportsHubRecords`); a table that can't be had is skipped and
    /// the cards stay as they are.
    func loadRecords() async {
        var queue = recordLeagues.filter { tablesAsked.insert($0).inserted }
        while !queue.isEmpty, !Task.isCancelled {
            let pair = Array(queue.prefix(2))
            queue.removeFirst(pair.count)
            // Side by side, without a task group (Swift 6.4 -O miscompiles them, see HomeStore).
            async let first = try? api.sportsStandings(pair[0])
            async let second = pair.count > 1 ? (try? api.sportsStandings(pair[1])) : nil
            for (league, answer) in zip(pair, await [first, second]) where answer?.available == true {
                tables[league] = answer?.groups
            }
        }
    }

    func loadPreferences() async {
        preferences = try? await api.sportsPreferences()
    }

    /// Reloads on the Expo hub's cadence until the view goes away.
    func poll() async {
        while !Task.isCancelled {
            let seconds: Int = if error != nil || hasLive { 30 }
                else if day == .today { 60 }
                else { 300 }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await load()
        }
    }
}
