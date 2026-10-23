import SwiftUI

/// The Search page's state, a port of the Expo `TVSearchScreen` and `useSearchTitles`:
/// Top 10 Today before anything is typed, then the movie, series and person
/// searches (400 ms after the last keystroke, 2+ characters) merged into one grid.
/// Owned by the Search tab's root, so the query and results survive a pushed details page.
@MainActor
final class SearchStore: ObservableObject {
    static let log = AppLog(category: "search")

    /// The text in the search field, clamped to Expo's 40 characters.
    @Published var query = "" {
        didSet {
            // Assigning inside `didSet` doesn't call it again.
            if query.count > SearchRanking.maxQueryLength { query = SearchRanking.clamp(query) }
            if trimmed(query) != trimmed(oldValue) { scheduleSearch() }
        }
    }
    /// Top 10 Today, the grid before anything is typed (the Expo catalog rail was dropped
    /// by user decision 2026-10-20).
    @Published private(set) var topTen: [Title] = []
    @Published private(set) var topTenLoading = false
    /// The merged results of `resultQuery`, and whether its searches are still running.
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var resultQuery: String?
    @Published private(set) var loading = false
    /// Total or partial failure of the current query's searches.
    @Published private(set) var notice: String?

    private var searchTask: Task<Void, Never>?
    private var topTenTask: Task<Void, Never>?
    private var topTenLoaded = false

    var normalizedQuery: String { trimmed(query) }
    var hasQuery: Bool { !normalizedQuery.isEmpty }

    /// What the grid shows: the current query's results, or Top 10 Today.
    var titles: [Title] {
        if hasQuery { return resultQuery == normalizedQuery ? results.map(\.title) : [] }
        return topTen
    }

    var isLoading: Bool { hasQuery ? loading : topTenLoading }

    /// The rail once a query is typed: the query and result names.
    var suggestions: [String] { SearchRanking.suggestions(query: normalizedQuery, titles: titles) }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Top 10

    /// Loads Top 10 Today once per visit, unless a query is showing.
    func loadTopTen() {
        guard !hasQuery, !topTenLoaded, topTenTask == nil else { return }
        topTenLoading = true
        topTenTask = Task {
            defer { topTenTask = nil }
            do {
                topTen = try await APIClient.shared.searchTopTen()
                topTenLoaded = true
                Self.log.info("top ten: \(topTen.count) titles")
            } catch {
                Self.log.error("top ten failed: \(error.localizedDescription)")
            }
            topTenLoading = false
        }
    }

    // MARK: Search

    /// Runs the current query again (the Retry button).
    func retry() { scheduleSearch(debounce: false) }

    private func scheduleSearch(debounce: Bool = true) {
        searchTask?.cancel()
        // The previous query's results and errors go as soon as the text changes.
        results = []
        resultQuery = nil
        notice = nil
        let query = normalizedQuery
        guard query.count >= SearchRanking.minQueryLength else {
            loading = false
            if query.isEmpty { loadTopTen() }
            return
        }
        loading = true
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: SearchRanking.debounce)
                guard !Task.isCancelled else { return }
            }
            await run(query)
        }
    }

    private func run(_ query: String) async {
        resultQuery = query
        let api = APIClient.shared
        let started = Date()
        async let movies = Self.attempt { try await api.search(query, type: "movie") }
        async let series = Self.attempt { try await api.search(query, type: "series") }
        async let people = Self.attempt { try await api.search(query, type: "person") }
        let outcomes = [("movie", await movies), ("series", await series), ("person", await people)]
        guard !Task.isCancelled else { return }
        var collected: [SearchResult] = []
        var failed = Set<String>()
        for (type, outcome) in outcomes {
            switch outcome {
            case .success(let found): collected += found
            case .failure(let error):
                failed.insert(type)
                Self.log.error("\(type) search failed: \(error.localizedDescription)")
            }
        }
        results = SearchRanking.merge(collected, query: query)
        notice = SearchRanking.failureNotice(failed)
        loading = false
        let personCount = results.filter { $0.title.mediaType == "person" }.count
        Self.log.info("\"\(query)\": \(results.count) results (\(personCount) people) in \(Int(Date().timeIntervalSince(started) * 1000)) ms"
            + (failed.isEmpty ? "" : ", failed: \(failed.sorted().joined(separator: ","))"))
    }

    private static func attempt(_ body: () async throws -> [SearchResult]) async -> Result<[SearchResult], Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }
}
