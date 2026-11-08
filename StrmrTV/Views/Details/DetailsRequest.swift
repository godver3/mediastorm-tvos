import Foundation

/// The details page's `PlaybackRequest` for the movie or one episode, shared by the TV page
/// (`DetailsView.request`) and the phone page (`MobileDetailsModel.request`), so both hand the
/// player the same episode info, Next Episode list, loading art and library copies.
enum DetailsRequest {
    static func make(target: DetailsTarget, title: Title?, seasons: [Season], episode: Episode?,
                     start: StartPoint?, seed: UInt64, library: LibraryVersions?) -> PlaybackRequest {
        PlaybackRequest(title: target, episode: episode.map(episodeInfo), start: start,
                        following: episode.map { airedEpisodes(after: $0, in: seasons) } ?? [],
                        artwork: .init(
                            backdropURLs: PlaybackRequest.Artwork.rotation(
                                still: episode?.image?.url,
                                primary: title?.backdrop?.url ?? target.backdropURL,
                                alternates: title?.backdrops?.map(\.url) ?? [],
                                showing: title?.backdrop?.url ?? target.backdropURL,
                                seed: seed),
                            logoURL: title?.logo?.url),
                        library: library)
    }

    static func episodeInfo(_ ep: Episode) -> PlaybackRequest.EpisodeInfo {
        PlaybackRequest.EpisodeInfo(season: ep.seasonNumber, episode: ep.episodeNumber,
                                    absolute: ep.absoluteEpisodeNumber, name: ep.name, itemID: ep.itemId,
                                    imageURL: ep.image?.url, overview: ep.overview, numbering: ep.numbering)
    }

    /// Regular-season episodes after `episode` that have aired, for Next Episode at the credits.
    static func airedEpisodes(after episode: Episode, in seasons: [Season]) -> [PlaybackRequest.EpisodeInfo] {
        let regular = seasons.filter { $0.number > 0 }.sorted { $0.number < $1.number }.flatMap(\.episodes)
        guard let index = regular.firstIndex(where: { $0.id == episode.id }) else { return [] }
        return regular[(index + 1)...]
            .prefix { ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
            .map(episodeInfo)
    }
}
