#if DEBUG
import AetherEngine
import UIKit

/// Debug-only: opens the VOD player straight on a URL, with no prequeue, so the player's
/// chrome can be checked without a resolvable source (on the simulator that is the software
/// route's HUD, which AetherEngine always takes there). Nothing is reported to the server.
/// Launch with `-StrmrPlayURL file:///path/clip.mkv`; `-StrmrPlayEpisode 1` plays it as an
/// episode (S1 E5, with E6 up next); `-StrmrPlayAction 1` shows a Skip Intro button after 3 s.
@MainActor
enum SoftwarePlayerProbe {
    static var url: URL? { UserDefaults.standard.string(forKey: "StrmrPlayURL").flatMap(URL.init(string:)) }

    static func present(_ url: URL) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let root = (scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first)?.rootViewController,
              let engine = try? AetherEngine() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { present(url) }
            return
        }
        let target = DetailsTarget(titleID: "probe", name: "Taskmaster", isMovie: false, year: 2015, tmdbID: nil,
                                   imdbID: nil, tvdbID: nil, posterURL: nil, textPosterURL: nil, backdropURL: nil,
                                   logoURL: nil, overview: "Probe playback.")
        let episode = UserDefaults.standard.bool(forKey: "StrmrPlayEpisode")
        let info = { (n: Int) in
            PlaybackRequest.EpisodeInfo(season: 1, episode: n, absolute: nil, name: "Episode \(n)", itemID: nil)
        }
        var request = PlaybackRequest(title: target, episode: episode ? info(5) : nil, start: nil)
        if episode { request.following = [info(6)] }
        request.reportsProgress = false
        let player = PlayerViewController(engine: engine, request: request, url: url, streamPath: "probe",
                                          tracks: TrackPreferences(selection: nil), previewsEnabled: false)
        root.present(player, animated: false)
        guard UserDefaults.standard.bool(forKey: "StrmrPlayAction") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            player.softwareHUD.setAction(UIAction(title: String(localized: "Skip Intro")) { _ in
                Task { await engine.seek(to: 90) }
            })
        }
    }
}
#endif
