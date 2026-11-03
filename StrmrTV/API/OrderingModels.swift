import Foundation

/// One of a series' alternate episode orderings (TVDB season types: aired, DVD, absolute, …).
struct SeriesOrdering: Decodable, Hashable, Identifiable {
    /// Lowercase season-type key (`official`, `dvd`, `absolute`, `alternate`, …).
    let type: String
    let name: String
    let seasonCount: Int?
    let isOfficial: Bool?

    var id: String { type }
}

/// The provider series and ordering an episode's season / episode numbers belong to. Sent back
/// with prequeue and source searches so the server resolves them in the same ordering.
struct EpisodeNumbering: Codable, Hashable {
    let seriesId: String
    let ordering: String?

    var json: [String: Any] {
        var o: [String: Any] = ["seriesId": seriesId]
        if let ordering, !ordering.isEmpty { o["ordering"] = ordering }
        return o
    }
}
