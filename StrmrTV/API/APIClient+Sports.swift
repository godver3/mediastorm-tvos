import Foundation

extension APIClient {
    func sportsStatus() async throws -> SportsStatus {
        try await send("GET", "/api/sports/status")
    }

    func sportsLeagues() async throws -> [SportsLeague] {
        let response: SportsLeaguesResponse = try await send("GET", "/api/sports/leagues")
        return response.leagues.elements
    }

    /// The cached scoreboard, or one ESPN day (`YYYY-MM-DD`, US Eastern) when the server
    /// answers dated queries.
    func sportsScoreboard(date: String?) async throws -> SportsScoreboard {
        try await send("GET", "/api/sports/scoreboard", query: date.map { ["date": $0] } ?? [:], timeout: 60)
    }

    func sportsGame(_ id: String) async throws -> SportsGame {
        try await send("GET", "/api/sports/game/\(Self.segment(id))", timeout: 60)
    }

    /// Channels that look like they carry the game. `broad` searches every source rather than
    /// the admin's default sources for the league (the Expo "Search more sources"). A race
    /// session or cycling stage names its `kind` (`racing`, `cycling`) and the weekend or race
    /// it belongs to (`parentId`).
    func sportsStreams(_ id: String, broad: Bool, kind: String? = nil, parentId: String? = nil) async throws -> [SportsStreamGroup] {
        var query = ["profileId": profileID]
        if broad { query["scope"] = "all" }
        if let kind { query["kind"] = kind }
        if let parentId { query["parentId"] = parentId }
        let response: SportsStreamsResponse = try await send("GET", "/api/sports/game/\(Self.segment(id))/streams",
                                                             query: query, timeout: 90)
        return response.groups?.elements ?? []
    }

    /// nil when the server has no per-profile sports preferences (404 from older servers).
    func sportsPreferences() async throws -> SportsPreferencesEnvelope? {
        do {
            return try await send("GET", "\(profilePath)/sports/preferences")
        } catch let APIError.http(failure) where failure.status == 404 {
            return nil
        }
    }

    /// Saves over `revision`; a 409 means another device saved first.
    func saveSportsPreferences(_ envelope: SportsPreferencesEnvelope) async throws -> SportsPreferencesEnvelope {
        let data = try JSONEncoder().encode(envelope)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return try await send("PUT", "\(profilePath)/sports/preferences", jsonObject: object)
    }
}
