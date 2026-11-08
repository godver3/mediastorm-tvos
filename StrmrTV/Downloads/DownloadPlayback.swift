#if os(iOS)
import AetherEngine
import UIKit

/// Plays a finished download in the regular player, from its local file: AetherEngine opens
/// `file://` URLs like any other source. Progress heartbeats still go to the server under the
/// title's ids, so watch history and resume carry over when it is reachable; offline they fail
/// quietly and are dropped, as in the Expo app. The player leaves out what needs the server for
/// a local file (Switch Source, Auto Switch, seek previews).
@MainActor
enum DownloadPlayback {
    /// The request the player reports progress for: the title and episode the download was
    /// made from, with no Up Next (only this file is on the device).
    static func request(_ item: DownloadItem, from start: StartPoint?) -> PlaybackRequest {
        let episode = item.seasonNumber.flatMap { season in
            item.episodeNumber.map { number in
                PlaybackRequest.EpisodeInfo(season: season, episode: number, absolute: nil, name: item.episodeName,
                                            itemID: item.episodeItemID, overview: item.episodeOverview)
            }
        }
        var request = PlaybackRequest(title: item.target, episode: episode, start: start)
        request.artwork = .init(backdropURLs: [item.backdropURL].compactMap { $0 }, logoURL: nil)
        return request
    }

    /// The server's resume point for the download's title, when it answers within a couple of
    /// seconds (offline it doesn't, and playback starts from the beginning).
    static func resumePoint(_ item: DownloadItem) async -> StartPoint? {
        let mediaType = item.isMovie ? "movie" : "episode"
        let itemID = item.progressItemID
        return await withTaskGroup(of: StartPoint?.self) { group in
            group.addTask { await APIClient.shared.resumeState(mediaType: mediaType, itemID: itemID)?.startPoint }
            group.addTask {
                try? await Task.sleep(for: .seconds(2.5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func play(_ item: DownloadItem, from start: StartPoint?) {
        let url = DownloadStorage.fileURL(item.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            PlaybackCoordinator.shared.errorMessage = String(localized: "The downloaded file is missing.")
            return
        }
        guard let engine = PlaybackCoordinator.shared.sharedEngine, let presenter = topViewController() else { return }
        DownloadSession.log.notice("playing download \(item.displayTitle, privacy: .public) from \(url.lastPathComponent, privacy: .public)")
        // `streamPath` stays the server path: online subtitles and skip segments look it up there.
        let player = PlayerViewController(engine: engine, request: request(item, from: start), url: url,
                                          streamPath: item.streamPath, tracks: TrackPreferences.library,
                                          previewsEnabled: false)
        player.currentSource = SourceSwitch.Current(releaseName: item.releaseName ?? item.fileName,
                                                    streamPath: item.streamPath,
                                                    origin: String(localized: "Downloaded"))
        presenter.present(player, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
#endif
