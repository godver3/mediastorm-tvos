import Foundation

extension APIClient {
    /// The organizers' race calendars (Expo `getSportsCycling`).
    func sportsCycling() async throws -> SportsCyclingFeed {
        try await send("GET", "/api/sports/cycling", timeout: 60)
    }

    /// A stage's own answer, with its classifications and route guide: `/sports/cycling/{race}/{year}/{n}`
    /// from the stage id `aso:tour:2026:21` (Expo `getSportsCyclingStage`).
    func sportsCyclingStage(_ stage: SportsCyclingStage) async throws -> SportsCyclingStage {
        guard let path = SportsCycling.stagePath(stage.id) else {
            throw APIError.notReady(String(localized: "This stage can't be loaded."))
        }
        return try await send("GET", "/api/sports/cycling/\(Self.segment(path.race))/\(Self.segment(path.year))/"
                              + Self.segment(path.number), timeout: 60)
    }

    /// A league's season tables (Expo `getSportsLeagueStandings`).
    func sportsStandings(_ league: String) async throws -> SportsLeagueStandings {
        try await send("GET", "/api/sports/standings/\(Self.segment(league))", timeout: 60)
    }
}
