import Foundation

extension APIClient {
    /// The Expo spoiler settings (`display.blurUnwatchedEpisode*`): unwatched episodes'
    /// thumbnails and overviews hidden on details pages, each with an "include the next
    /// episode" switch. Layered as the Expo app layers them: this device's override from
    /// `/api/clients/{id}/settings` (top-level there), then the profile's display settings
    /// (the server's defaults already filled in). Nil members when neither answers.
    struct EpisodePrivacy: Equatable {
        var blurThumbnails: Bool?
        var thumbnailsIncludeNext: Bool?
        var blurOverviews: Bool?
        var overviewsIncludeNext: Bool?
    }

    func episodePrivacy() async -> EpisodePrivacy {
        struct Values: Decodable {
            let blurUnwatchedEpisodeThumbnails: Bool?
            let blurUnwatchedEpisodeThumbnailsIncludeCurrent: Bool?
            let blurUnwatchedEpisodeOverviews: Bool?
            let blurUnwatchedEpisodeOverviewsIncludeCurrent: Bool?
        }
        struct UserSettings: Decodable { let display: Values? }

        async let user: UserSettings? = try? await send("GET", "/api/users/\(Self.segment(profileID))/settings",
                                                        promptOnLock: false, timeout: 10)
        async let device: Values? = try? await send("GET", "/api/clients/\(Self.segment(Config.clientID))/settings",
                                                    query: ["userId": profileID], promptOnLock: false, timeout: 10)
        let (u, d) = await (user?.display, device)
        return EpisodePrivacy(
            blurThumbnails: d?.blurUnwatchedEpisodeThumbnails ?? u?.blurUnwatchedEpisodeThumbnails,
            thumbnailsIncludeNext: d?.blurUnwatchedEpisodeThumbnailsIncludeCurrent
                ?? u?.blurUnwatchedEpisodeThumbnailsIncludeCurrent,
            blurOverviews: d?.blurUnwatchedEpisodeOverviews ?? u?.blurUnwatchedEpisodeOverviews,
            overviewsIncludeNext: d?.blurUnwatchedEpisodeOverviewsIncludeCurrent
                ?? u?.blurUnwatchedEpisodeOverviewsIncludeCurrent)
    }
}
