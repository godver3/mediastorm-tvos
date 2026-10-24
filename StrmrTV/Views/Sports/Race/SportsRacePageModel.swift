import Foundation

/// The race page's tabs; Championship is MotoGP's riders' standings.
enum SportsRaceTab: String, CaseIterable, Identifiable {
    case overview, timing, championship

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .timing: String(localized: "Timing")
        case .championship: String(localized: "Championship")
        }
    }
}

/// The race page's data (Expo `RaceScreen` and `SportsRaceDetailTV` state): the weekend from the
/// race board, the shown session and its latest snapshot, and the extras each series has (F1's
/// timing archive, MotoGP's circuit guide and championship), each loaded on its own schedule by
/// `SportsRaceView`.
@MainActor
final class SportsRacePageModel: ObservableObject {
    @Published private(set) var weekend: SportsRaceEvent?
    /// Why there is no weekend to show.
    @Published private(set) var missing: String?
    @Published private(set) var boardFailed = false
    @Published private(set) var selectedID: String?
    @Published private var result: SportsRaceEvent?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published var tab: SportsRaceTab = .overview
    /// The entry the driver card and comparison show (Expo `competitorId`).
    @Published var competitorID: String?
    /// Timing's result filter ("Retired"…); nil shows every entry.
    @Published var resultFilter: String?
    /// The Timing row showing its labelled statistics.
    @Published var expandedID: String?
    @Published private(set) var archive: SportsF1Archive?
    @Published private(set) var guide: SportsMotoGPEnrichment?
    @Published private(set) var guideFailed = false
    @Published private(set) var standings: SportsMotoGPEnrichment?
    @Published private(set) var standingsFailed = false
    /// Bumped by Try Again; every load restarts on it.
    @Published private(set) var retries = 0

    private let weekendID: String
    private let api = APIClient.shared

    /// The hub's board shows the weekend at once; `loadWeekend()` brings a fresh one.
    init(weekendID: String, sessionID: String?, board: SportsRaceBoard?) {
        self.weekendID = weekendID
        selectedID = sessionID
        if let found = board?.resolve(weekendID) {
            weekend = found.weekend
            if selectedID == nil { selectedID = found.session }
        }
    }

    /// The session shown: the one picked, else the weekend's default (Expo `defaultRaceSession`).
    var session: SportsRaceEvent? {
        guard let weekend else { return nil }
        return weekend.sessions.first { $0.id == selectedID } ?? weekend.defaultSession
    }

    /// The shown session's latest snapshot: its own answer once it has come, else the board's copy.
    var detail: SportsRaceEvent? {
        guard let session else { return nil }
        if let result, result.id == session.id { return result }
        return session
    }

    var competitor: SportsRaceDriver? {
        guard let all = detail?.participants else { return nil }
        return all.first { $0.id == competitorID } ?? all.first
    }

    /// Updates are late: a failed load, or the provider marked the weekend or session stale.
    var delayed: Bool { boardFailed || failed || detail?.stale == true || weekend?.stale == true }

    /// The results Timing can filter by, when there are two or more (Expo `resultStatuses`).
    var resultStatuses: [String] {
        var seen: [String] = []
        for result in (detail?.participants ?? []).compactMap(\.result)
        where result.range(of: #"^(Classified|Retired|DNF|DNS|DSQ|Disqualified|Finished)$"#,
                           options: [.regularExpression, .caseInsensitive]) != nil && !seen.contains(result) {
            seen.append(result)
        }
        return seen.count > 1 ? seen : []
    }

    var activeFilter: String? { resultFilter.flatMap { resultStatuses.contains($0) ? $0 : nil } }

    /// The entries shown, after the result filter.
    var entries: [SportsRaceDriver] {
        let filter = activeFilter
        return (detail?.participants ?? []).filter { filter == nil || $0.result == filter }
    }

    /// The shown session's F1 timing archive, embedded or fetched.
    var timingArchive: SportsF1Archive? {
        guard let detail else { return nil }
        let found = detail.f1Archive ?? archive.flatMap { $0.eventId == detail.id ? $0 : nil }
        return found?.available == true ? found : nil
    }

    var tabs: [SportsRaceTab] { weekend?.riders == true ? SportsRaceTab.allCases : [.overview, .timing] }

    func select(_ sessionID: String) {
        selectedID = sessionID
        resultFilter = nil
        expandedID = nil
        if tab == .championship { tab = .overview }
    }

    func retry() { retries += 1 }

    /// The weekend from a fresh race board (Expo reloads it whenever the page shows).
    func loadWeekend() async {
        do {
            let found = try await api.sportsRaces().resolve(weekendID)
            if let found {
                weekend = found.weekend
                if selectedID == nil { selectedID = found.session }
                missing = nil
            } else if weekend == nil {
                missing = String(localized: "This race weekend is no longer in the current feed.")
            }
            boardFailed = found == nil
        } catch {
            guard !Task.isCancelled else { return }
            boardFailed = true
            if weekend == nil { missing = String(localized: "Race weekends could not be reached.") }
        }
    }

    /// Reloads the shown session every 30 s, every 10 min once final, keeping the last answer through failures.
    func pollSession() async {
        guard let shown = session else { return }
        loading = true
        failed = false
        while !Task.isCancelled {
            do {
                result = try await api.sportsRaceSession(shown)
                failed = false
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
            loading = false
            let latest = result.flatMap { $0.id == shown.id ? $0 : nil } ?? shown
            try? await Task.sleep(for: .seconds(latest.isFinal ? 600 : 30))
        }
    }

    /// F1's timing archive, for a finished F1 session that doesn't carry one.
    func loadArchive() async {
        guard let shown = detail, shown.league == "f1", shown.isFinal, shown.f1Archive == nil,
              archive?.eventId != shown.id else { return }
        if let answer = try? await api.sportsF1Archive(shown) { archive = answer }
    }

    /// The organizer's circuit guide, for a MotoGP weekend without reference geometry.
    func loadGuide() async {
        guard let shown = weekend, shown.riders, shown.circuit == nil else { return }
        guideFailed = false
        do {
            guide = try await api.sportsMotoGPCircuit(shown)
        } catch {
            if !Task.isCancelled { guideFailed = true }
        }
    }

    /// The MotoGP championship, every 5 min while its tab shows.
    func pollStandings() async {
        while !Task.isCancelled {
            do {
                standings = try await api.sportsMotoGPStandings()
                standingsFailed = false
            } catch {
                guard !Task.isCancelled else { return }
                standingsFailed = true
            }
            try? await Task.sleep(for: .seconds(300))
        }
    }
}
