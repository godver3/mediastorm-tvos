import Foundation

/// The ranked sources for one playback, in the details page's source picker's order
/// (`SourceSearch`): the picker's own results for this title / episode when it searched
/// recently, so the two lists match, else a search with the same call. Pending cache /
/// health checks resolve in the background, so a later visit shows them.
@MainActor
final class SourceSwitchList {
    private(set) var results: [SourceResult] = []
    private(set) var health: [Int: SourceHealth] = [:]
    private var search: Task<Result<[SourceResult], Error>, Never>?
    private var healthTask: Task<Void, Never>?
    private let request: PlaybackRequest

    init(request: PlaybackRequest) {
        self.request = request
    }

    private var query: String {
        SourceSearch.query(name: request.title.name, year: request.title.year,
                           episode: request.episode.map { ($0.season, $0.episode) })
    }

    func cancel() {
        search?.cancel()
        healthTask?.cancel()
    }

    /// The picker's recent results, else searches the first time (a failed search is
    /// retried on the next call).
    func load() async throws -> [SourceResult] {
        if results.isEmpty, let recent = SourceSearch.recent(title: request.title, query: query) {
            results = recent.results
            health = recent.health
            return results
        }
        if search == nil {
            let title = request.title
            let query = query
            search = Task {
                do { return .success(try await SourceSearch.search(title: title, query: query)) } catch { return .failure(error) }
            }
        }
        switch await search!.value {
        case let .success(results):
            if self.results.isEmpty, !results.isEmpty { adopt(results) }
            return self.results
        case let .failure(error):
            search = nil
            throw error
        }
    }

    private func adopt(_ results: [SourceResult]) {
        self.results = results
        health = SourceSearch.initialHealth(results)
        let tokens = Set(health.values.filter { $0.state == "pending" }.compactMap(\.token))
        guard !tokens.isEmpty else { return }
        let title = request.title
        let query = query
        healthTask = Task { [weak self] in
            for token in tokens {
                var complete = false
                while !complete, !Task.isCancelled {
                    guard let snapshot = try? await APIClient.shared.sourceHealth(token: token) else { break }
                    for entry in snapshot.results {
                        self?.health[entry.index] = entry.health
                        SourceSearch.updateHealth(title: title, query: query, index: entry.index, health: entry.health)
                    }
                    complete = snapshot.complete
                }
            }
        }
    }
}
