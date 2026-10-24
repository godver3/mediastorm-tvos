import Foundation

extension APIClient {
    /// The race weekends in the providers' window, with every series' feed state.
    func sportsRaces() async throws -> SportsRaceBoard {
        try await send("GET", "/api/sports/races", timeout: 60)
    }

    /// A session's latest snapshot: its entries or classification, with each entry's timing.
    func sportsRaceSession(_ session: SportsRaceEvent) async throws -> SportsRaceEvent {
        try await send("GET", "/api/sports/races/\(Self.segment(session.league))/\(Self.segment(session.providerEventId))/"
                       + Self.segment(session.sessionId ?? ""), timeout: 60)
    }

    /// The MotoGP riders' championship.
    func sportsMotoGPStandings() async throws -> SportsMotoGPEnrichment {
        try await send("GET", "/api/sports/motogp/standings")
    }

    /// The organizer's guide to the circuit of a MotoGP weekend.
    func sportsMotoGPCircuit(_ weekend: SportsRaceEvent) async throws -> SportsMotoGPEnrichment {
        try await send("GET", "/api/sports/motogp/circuit/\(Self.segment(weekend.providerEventId))")
    }

    /// F1's timing archive of a finished session.
    func sportsF1Archive(_ session: SportsRaceEvent) async throws -> SportsF1Archive {
        try await send("GET", "/api/sports/f1/archive/\(Self.segment(session.providerEventId))/"
                       + Self.segment(session.sessionId ?? ""), timeout: 60)
    }
}
