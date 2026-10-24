import Foundation

/// A league's standings while they show (Expo `SportsLeagueStandings` state): the provider's
/// answer, reloaded every 5 min and kept through failures, the chosen table and the row showing
/// every statistic.
@MainActor
final class SportsStandingsModel: ObservableObject {
    let league: String
    @Published private(set) var standings: SportsLeagueStandings?
    @Published private(set) var failed = false
    @Published private(set) var groupID: String?
    /// The row showing every column.
    @Published var expandedID: String?
    /// Bumped by Try Again; the poll restarts on it.
    @Published private(set) var retries = 0

    init(league: String) { self.league = league }

    /// The chosen table, else the first.
    var table: SportsLeagueTable? {
        guard let groups = standings?.groups else { return nil }
        return groups.first { $0.id == groupID } ?? groups.first
    }

    func choose(_ id: String) {
        groupID = id
        expandedID = nil
    }

    func retry() { retries += 1 }

    func poll() async {
        while !Task.isCancelled {
            do {
                standings = try await APIClient.shared.sportsStandings(league)
                failed = false
            } catch {
                if error is CancellationError || Task.isCancelled { return }
                failed = true
            }
            try? await Task.sleep(for: .seconds(300))
        }
    }
}
