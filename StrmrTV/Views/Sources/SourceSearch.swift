import Foundation

/// The manual source list's search, order and health, shared by the details page's source
/// picker and the player's Switch Source list, so the two show the same
/// sources in the same order.
///
/// Both lists used to run their own `/api/indexers/search`, minutes apart: the indexers, the
/// remembered usenet health and the adaptive caps can change between the two, so the
/// server's ranking (and its order among equal ranks) came back different. Now the picker's
/// latest results are kept per title / episode, and Switch Source shows those, in the same
/// `ordered` order with the same health; it searches itself only when the picker hasn't
/// searched in the last `maxAge`.
@MainActor
enum SourceSearch {
    struct Key: Hashable {
        let titleID: String
        let query: String
    }

    struct Snapshot {
        var results: [SourceResult]
        var health: [Int: SourceHealth]
        let at: Date
    }

    /// How long a search is reused by Switch Source.
    static let maxAge: TimeInterval = 30 * 60
    private static var snapshots: [Key: Snapshot] = [:]

    /// The search query ("Name S01E02", or "Name 2024").
    nonisolated static func query(name: String, year: Int?, episode: (season: Int, episode: Int)?) -> String {
        if let episode { return name + String(format: " S%02dE%02d", episode.season, episode.episode) }
        if let year { return "\(name) \(year)" }
        return name
    }

    /// The list's order: the server's rank (its response order), the one order both lists use.
    nonisolated static func ordered(_ results: [SourceResult]) -> [SourceResult] {
        results.sorted { $0.index < $1.index }
    }

    /// The health a result starts with: the search's own annotation.
    nonisolated static func initialHealth(_ results: [SourceResult]) -> [Int: SourceHealth] {
        Dictionary(results.compactMap { r in r.health.map { (r.index, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Searches and keeps the results for this title / episode (the source picker, and
    /// Switch Source when nothing recent is kept).
    static func search(title: DetailsTarget, query: String) async throws -> [SourceResult] {
        let results = ordered(try await APIClient.shared.searchSources(query: query, title: title))
        snapshots[Key(titleID: title.titleID, query: query)] =
            Snapshot(results: results, health: initialHealth(results), at: Date())
        return results
    }

    /// The results kept for this title / episode, if recent enough.
    static func recent(title: DetailsTarget, query: String, now: Date = Date()) -> Snapshot? {
        guard let snapshot = snapshots[Key(titleID: title.titleID, query: query)],
              now.timeIntervalSince(snapshot.at) < maxAge else { return nil }
        return snapshot
    }

    /// Records a result's latest health (a resolved check or a probe), so the other list
    /// shows it too.
    static func updateHealth(title: DetailsTarget, query: String, index: Int, health: SourceHealth) {
        snapshots[Key(titleID: title.titleID, query: query)]?.health[index] = health
    }
}
