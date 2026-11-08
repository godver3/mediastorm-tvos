#if os(iOS)
import SwiftUI

/// Download and Download Season (More Options, an episode's menu), as the Expo phone page:
/// pick a release ranked for downloading, resolve it, queue it in `DownloadManager`. A season
/// takes one pack and resolves every episode's file from it in one batch (one by one when the
/// server can't batch it).
extension MobileDetailsModel {
    struct DownloadRequest: Identifiable {
        let target: DetailsTarget
        let episode: Episode?
        let season: Season?
        let heading: String
        var id: String { "\(episode?.id ?? "")|\(season?.id ?? "")" }
    }

    /// The page's title with the art and overview the details load filled in, which the
    /// download keeps for the Downloads list and for offline playback.
    var downloadTarget: DetailsTarget {
        let t = target
        return DetailsTarget(titleID: t.titleID, name: title?.name ?? t.name, isMovie: t.isMovie, year: title?.year ?? t.year,
                             tmdbID: t.tmdbID ?? title?.tmdbId.map(String.init), imdbID: t.imdbID ?? title?.imdbId,
                             tvdbID: t.tvdbID ?? title?.tvdbId.map(String.init), posterURL: title?.poster?.url ?? t.posterURL,
                             textPosterURL: nil, backdropURL: title?.backdrop?.url ?? t.backdropURL, logoURL: nil,
                             overview: title?.overview ?? t.overview)
    }

    func download(for episode: Episode?) -> DownloadItem? {
        DownloadManager.shared.download(for: target, episode: target.isMovie ? nil : episode)
    }

    func requestDownload(_ episode: Episode?) {
        let ep = target.isMovie ? nil : episode
        downloadRequest = DownloadRequest(target: downloadTarget, episode: ep, season: nil,
                                          heading: ep.map { "\(target.name) · \($0.code)" } ?? target.name)
    }

    func requestSeasonDownload(_ season: Season) {
        downloadRequest = DownloadRequest(target: downloadTarget, episode: nil, season: season,
                                          heading: "\(target.name) · \(WatchStateSeasons.name(season))")
    }

    /// Resolves the picked release and queues it; returns the toast to show.
    func queueDownload(_ result: SourceResult, for request: DownloadRequest) async -> String {
        if let season = request.season { return await queueSeason(result, season: season, target: request.target) }
        do {
            let resolved = try await APIClient.shared.resolveSource(result, titleID: request.target.titleID, startOffset: nil)
            try DownloadManager.shared.start(target: request.target, episode: request.episode, streamPath: resolved.path,
                                             releaseName: SourceSwitch.releaseName(result), expectedBytes: result.sizeBytes)
            return String(localized: "Download started")
        } catch {
            return error.localizedDescription
        }
    }

    private func queueSeason(_ result: SourceResult, season: Season, target: DetailsTarget) async -> String {
        let episodes = season.episodes.filter { ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
        guard !episodes.isEmpty else { return String(localized: "No episodes to download") }
        var queued = 0
        var failed = 0
        var lastError: String?
        let release = SourceSwitch.releaseName(result)
        func queue(_ ep: Episode, path: String?, size: Int64?) {
            guard let path, !path.isEmpty else { failed += 1; return }
            do {
                try DownloadManager.shared.start(target: target, episode: ep, streamPath: path, releaseName: release,
                                                 expectedBytes: size ?? 0)
                queued += 1
            } catch {
                failed += 1
                lastError = error.localizedDescription
            }
        }
        if let batch = try? await APIClient.shared.resolveBatch(result, episodes: episodes), !batch.isEmpty {
            for entry in batch {
                guard let ep = episodes.first(where: {
                    $0.seasonNumber == entry.seasonNumber && $0.episodeNumber == entry.episodeNumber
                }) else { continue }
                queue(ep, path: entry.resolution?.webdavPath, size: entry.resolution?.fileSize)
            }
        } else {
            // One by one, each episode targeted in the pack.
            for ep in episodes {
                var raw = result.raw
                var attributes = (raw["attributes"] as? [String: Any]) ?? [:]
                attributes["targetSeason"] = String(ep.seasonNumber)
                attributes["targetEpisode"] = String(ep.episodeNumber)
                attributes["targetEpisodeCode"] = ep.code
                raw["attributes"] = attributes
                guard let targeted = SourceResult(raw, index: result.index),
                      let resolved = try? await APIClient.shared.resolveSource(targeted, titleID: target.titleID,
                                                                               startOffset: nil) else {
                    failed += 1
                    continue
                }
                queue(ep, path: resolved.path, size: nil)
            }
        }
        if queued == 0 { return lastError ?? String(localized: "No episodes could be downloaded") }
        if failed == 0 { return String(localized: "Downloading \(queued) episodes") }
        return String(localized: "Downloading \(queued) episodes; \(failed) failed")
    }
}

/// The page's download sheet and its outcome toast; the More menu and the episode menus open it.
struct MobileDetailsDownloads: ViewModifier {
    @ObservedObject var model: MobileDetailsModel
    @EnvironmentObject private var titles: TitleStateStore

    func body(content: Content) -> some View {
        content.sheet(item: $model.downloadRequest) { request in
            MobileDownloadSourcePicker(request: request) { result in
                titles.show(toast: request.season == nil ? String(localized: "Preparing download…")
                                                         : String(localized: "Preparing episodes…"))
                Task { titles.show(toast: await model.queueDownload(result, for: request)) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
#endif
