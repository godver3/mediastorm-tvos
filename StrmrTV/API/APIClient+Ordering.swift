import Foundation

extension APIClient {
    /// Saves the profile's episode ordering for a series (`PUT /series-ordering/{tvdbId}`), which
    /// `/details-bundle` then applies. The official ordering clears the choice. A non-official
    /// one turns off Trakt / Simkl scrobbling for the series on the server, as in the Expo app.
    func setSeriesOrdering(tvdbID: Int, seasonType: String) async throws {
        struct Reply: Decodable, Sendable { let seasonType: String? }
        let _: Reply = try await send("PUT", "\(profilePath)/series-ordering/\(tvdbID)",
                                      jsonObject: ["seasonType": seasonType])
    }
}
