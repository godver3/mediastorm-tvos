#if os(iOS)
import SwiftUI

/// The download entries in More Options and an episode's menu: Download… (the movie, or the
/// episode Play targets), Download Season… for series, and once a download exists its state
/// with Play Download / Pause / Resume / Delete Download.
extension MobileDetailsView {
    var downloadItems: some View {
        MobileDetailsDownloadItems(model: model, episode: target.isMovie ? nil : model.activeEpisode, offersSeasons: true)
    }

    func episodeDownloadItem(_ episode: Episode) -> some View {
        MobileDetailsDownloadItems(model: model, episode: episode, offersSeasons: false)
    }
}

/// Menu rows for one movie / episode's download (observes the manager, so a menu opened
/// mid-download shows its progress).
struct MobileDetailsDownloadItems: View {
    @ObservedObject var model: MobileDetailsModel
    let episode: Episode?
    let offersSeasons: Bool
    @ObservedObject private var manager = DownloadManager.shared

    var body: some View {
        Section {
            let canDownload = model.target.isMovie || episode != nil
            if let item = model.download(for: episode) {
                existing(item)
            } else if canDownload {
                Button { model.requestDownload(episode) } label: {
                    Label(episode.map { String(localized: "Download \($0.code)…") } ?? String(localized: "Download…"),
                          systemImage: "arrow.down.circle")
                }
            }
            if offersSeasons, !model.target.isMovie, !model.visibleSeasons.isEmpty {
                Menu {
                    ForEach(model.visibleSeasons) { season in
                        Button(WatchStateSeasons.name(season)) { model.requestSeasonDownload(season) }
                            .disabled(season.episodes.isEmpty)
                    }
                } label: {
                    Label("Download Season", systemImage: "square.and.arrow.down.on.square")
                }
            }
        }
    }

    @ViewBuilder
    private func existing(_ item: DownloadItem) -> some View {
        switch item.status {
        case .completed:
            Button { DownloadPlayback.play(item, from: model.resumePoint(episode)) } label: {
                Label("Play Download", systemImage: "arrow.down.circle.fill")
            }
        case .downloading, .pending:
            Button { manager.pause(item.id) } label: {
                Label("Downloading \(Int((item.progress * 100).rounded()))% · Pause", systemImage: "pause.circle")
            }
        case .paused, .failed:
            Button { manager.resume(item.id) } label: {
                Label(item.status == .paused ? String(localized: "Resume Download") : String(localized: "Retry Download"),
                      systemImage: "arrow.down.circle")
            }
        }
        Button(role: .destructive) { manager.delete(item.id) } label: {
            Label(item.isActive ? String(localized: "Cancel Download") : String(localized: "Delete Download"),
                  systemImage: "trash")
        }
    }
}
#endif
