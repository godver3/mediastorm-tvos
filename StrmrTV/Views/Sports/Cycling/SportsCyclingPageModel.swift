import Foundation

/// The cycling page's tabs (Expo's Stage|Race overview, Overall GC, Route|Source): the shown
/// stage's results, the overall standings after it, and the organizer's stage guide.
enum SportsCyclingTab: String, CaseIterable, Identifiable {
    case overview, overall, route

    var id: String { rawValue }

    func label(_ race: SportsCyclingRace) -> String {
        switch self {
        case .overview: SportsCyclingFormat.overviewTab(race)
        case .overall: String(localized: "Overall GC")
        case .route: race.calendarOnly ? String(localized: "Source") : String(localized: "Route")
        }
    }
}

/// The cycling page's data (Expo `CyclingScreen` and `SportsCyclingDetailTV` state): the race from
/// the cycling calendar, the shown stage and its own answer (reloaded every 5 min, never for a
/// dates-only race), the tab, the result filter and the page of riders.
@MainActor
final class SportsCyclingPageModel: ObservableObject {
    static let pageSize = 20

    @Published private(set) var race: SportsCyclingRace?
    /// Why there is no race to show.
    @Published private(set) var missing: String?
    @Published private(set) var feedFailed = false
    @Published private(set) var selectedID: String?
    @Published private var answer: SportsCyclingStage?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var tab: SportsCyclingTab = .overview
    /// DNF, DNS or DSQ; nil shows everyone.
    @Published private(set) var resultFilter: String?
    /// The page of `pageSize` entries shown.
    @Published var page = 0
    /// Bumped by Try Again; every load restarts on it.
    @Published private(set) var retries = 0

    private let raceID: String
    private let api = APIClient.shared

    /// The hub's calendar shows the race at once; `loadRace()` brings a fresh one.
    init(raceID: String, stageID: String?, feed: SportsCyclingFeed?) {
        self.raceID = raceID
        selectedID = stageID
        race = feed?.races.first { $0.id == raceID }
    }

    /// The stage shown: the one picked, else the latest one on or before today (Expo `defaultCyclingStage`).
    var stage: SportsCyclingStage? {
        guard let race else { return nil }
        return race.stages.first { $0.id == selectedID } ?? SportsCycling.defaultStage(race)
    }

    /// The shown stage's latest answer, else the calendar's copy.
    var detail: SportsCyclingStage? {
        guard let stage else { return nil }
        if let answer, answer.id == stage.id { return answer }
        return stage
    }

    var tabs: [SportsCyclingTab] {
        guard let race else { return [] }
        return race.oneDay || race.championship || race.scheduleOnly ? [.overview, .route] : SportsCyclingTab.allCases
    }

    /// A team time trial's stage shows its team classification.
    var teamStage: Bool { race?.oneDay == false && tab == .overview && detail?.teamResults != nil }

    /// The classification the results tab lists.
    var classification: SportsCyclingResults? {
        guard let shown = detail else { return nil }
        if teamStage { return shown.teamResults }
        if race?.oneDay == true || tab != .overall { return shown.results }
        return shown.generalClassification
    }

    var rows: [SportsCyclingResult] { classification?.rows ?? [] }

    /// DNF / DNS / DSQ among the rows, in order of appearance.
    var resultStatuses: [String] {
        var seen = Set<String>()
        return rows.compactMap { $0.result?.isEmpty == false ? $0.result : nil }.filter { seen.insert($0).inserted }
    }

    var activeFilter: String? { resultFilter.flatMap { resultStatuses.contains($0) ? $0 : nil } }

    var filtered: [SportsCyclingResult] { rows.filter { activeFilter == nil || $0.result == activeFilter } }

    var pages: Int { max(1, (filtered.count + Self.pageSize - 1) / Self.pageSize) }

    var currentPage: Int { min(max(page, 0), pages - 1) }

    var visible: [SportsCyclingResult] { Array(filtered.dropFirst(currentPage * Self.pageSize).prefix(Self.pageSize)) }

    /// Updates are late: a failed load, or the classification is a saved one.
    var delayed: Bool { feedFailed || failed || classification?.stale == true }

    /// What Find Streams searches for: the stage with its race, while it can still be found
    /// (Expo `cyclingWatchTarget`).
    var watchTarget: SportsWatchTarget? {
        guard let race, let stage, SportsCycling.canSearch(race, stage) else { return nil }
        return SportsWatchTarget(id: stage.id, title: "\(race.name) · \(stage.name)", live: false, kind: SportsCycling.sport,
                                 parentID: race.id, noun: String(localized: "stage"))
    }

    func select(_ stageID: String) {
        selectedID = stageID
        resetResults()
    }

    func show(_ tab: SportsCyclingTab) {
        self.tab = tab
        resetResults()
    }

    func filter(_ status: String?) {
        resultFilter = status
        page = 0
    }

    private func resetResults() {
        resultFilter = nil
        page = 0
    }

    func retry() { retries += 1 }

    /// The race from a fresh calendar (Expo reloads it whenever the page shows).
    func loadRace() async {
        do {
            let found = try await api.sportsCycling().races.first { $0.id == raceID }
            if let found {
                race = found
                missing = nil
            } else if race == nil {
                missing = String(localized: "This cycling race is not available in the current feed.")
            }
            feedFailed = false
        } catch {
            guard !(error is CancellationError) else { return }
            feedFailed = true
            if race == nil { missing = String(localized: "Cycling coverage could not be reached.") }
        }
    }

    /// Reloads the shown stage every 5 min, keeping the last answer through failures; a
    /// dates-only race has none.
    func pollStage() async {
        guard let shown = stage, race?.scheduleOnly != true else { return }
        loading = true
        failed = false
        while !Task.isCancelled {
            do {
                answer = try await api.sportsCyclingStage(shown)
                failed = false
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                failed = true
            }
            loading = false
            try? await Task.sleep(for: .seconds(300))
        }
    }
}
