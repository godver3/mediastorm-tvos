import Foundation

/// Search and the Top 10 Today the Search page shows before typing, on the endpoints the
/// Expo TV search uses (`services/api.ts`).
extension APIClient {
    /// `GET /api/search?q=&type=movie|series|person&userId=`. The server drops people
    /// (and applies rating limits) for kids profiles.
    func search(_ query: String, type: String) async throws -> [SearchResult] {
        try await send("GET", "/api/search", query: ["q": query, "type": type, "userId": profileID])
    }

    /// Top 10 Today, the Search page's grid before anything is typed.
    func searchTopTen() async throws -> [Title] {
        // Trending can take a long time on a cold server cache.
        let top: TopTenPage = try await send("GET", "/api/discover/top-ten", query: ["userId": profileID], timeout: 60)
        return top.items.map(\.title)
    }
}

private struct TopTenPage: Decodable {
    let items: [TrendingItem]
}
