import Foundation

/// The details page's related rows: a movie's collection and a cast member's filmography.
/// (More Like This comes in the details bundle.)
extension APIClient {
    /// A collection's movies in release order (undated last), as the Expo details page sorts them.
    func collectionMovies(id: Int) async throws -> [Title] {
        let details: CollectionDetails = try await send("GET", "/api/metadata/collection", query: ["id": String(id)])
        return (details.movies ?? []).sorted {
            let a = ($0.year ?? 0) > 0 ? $0.year! : .max
            let b = ($1.year ?? 0) > 0 ? $1.year! : .max
            return a != b ? a < b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// `GET /api/metadata/person`: the person and their filmography.
    func person(id: Int) async throws -> PersonDetails {
        try await send("GET", "/api/metadata/person", query: ["id": String(id)])
    }
}
