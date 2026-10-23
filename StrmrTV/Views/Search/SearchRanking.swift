import Foundation

/// The pure parts of the Expo TV search (`hooks/useApi.ts` `useSearchTitles`,
/// `components/search/person-results.ts`, `TVSearchScreen.tsx`), ported for testing.
enum SearchRanking {
    static let minQueryLength = 2
    static let maxQueryLength = 40
    static let debounce: Duration = .milliseconds(400)
    /// The three searches, in the order Expo sends them; each is a `type=` value.
    static let types = ["movie", "series", "person"]

    /// `normalizedName`: NFKC, trimmed, inner whitespace collapsed, lower-cased.
    static func normalizedName(_ name: String) -> String {
        name.precomposedStringWithCompatibilityMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .lowercased()
    }

    /// A person whose name is the query, which Expo puts ahead of every other result.
    static func isExactPersonMatch(_ title: Title, query: String) -> Bool {
        title.mediaType == "person" && normalizedName(title.name) == normalizedName(query)
    }

    /// `mergeAndSortResults`: one result per title ID (the higher score wins), exact
    /// person matches first, then by score; ties keep the order the results arrived in.
    static func merge(_ results: [SearchResult], query: String) -> [SearchResult] {
        var order: [String] = []
        var best: [String: SearchResult] = [:]
        for result in results {
            let t = result.title
            let key = t.id.isEmpty
                ? "\(t.mediaType)-\(t.name.lowercased())-\(t.year.map(String.init) ?? "unknown")" : t.id
            if let existing = best[key] {
                if (existing.score ?? 0) < (result.score ?? 0) { best[key] = result }
            } else {
                order.append(key)
                best[key] = result
            }
        }
        let deduped = order.compactMap { best[$0] }
        return deduped.enumerated().sorted { a, b in
            let ea = isExactPersonMatch(a.element.title, query: query), eb = isExactPersonMatch(b.element.title, query: query)
            if ea != eb { return ea }
            let sa = a.element.score ?? 0, sb = b.element.score ?? 0
            return sa != sb ? sa > sb : a.offset < b.offset
        }.map(\.element)
    }

    /// The rail while a query is typed: the query, then result names, unique, at most 8.
    static func suggestions(query: String, titles: [Title]) -> [String] {
        var seen = Set<String>()
        return ([query] + titles.map(\.name)).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    /// The notice for searches that failed, by `type=`; nil when none did.
    static func failureNotice(_ failed: Set<String>) -> String? {
        if failed.isEmpty { return nil }
        if failed.count == types.count { return String(localized: "Search couldn’t complete. Please try again.") }
        let names = [("movie", "Movie"), ("series", "TV show"), ("person", "Actor")]
            .filter { failed.contains($0.0) }.map(\.1).joined(separator: " and ")
        return String(localized: "\(names) search is unavailable. Results may be incomplete.")
    }

    /// The query as Expo keeps it: at most 40 characters.
    static func clamp(_ query: String) -> String { String(query.prefix(maxQueryLength)) }
}
