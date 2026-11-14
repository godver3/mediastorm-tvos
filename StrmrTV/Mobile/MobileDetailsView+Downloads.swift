#if os(iOS)
import Combine
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

/// Menu rows for one movie / episode's download. They observe `DownloadStatusIndex`, not the
/// manager: progress republishes the manager's items several times a second, and every
/// re-render rebuilds an open UIMenu (its submenus collapse and reopen, so the menu blinks).
struct MobileDetailsDownloadItems: View {
    @ObservedObject var model: MobileDetailsModel
    let episode: Episode?
    let offersSeasons: Bool
    @ObservedObject private var statuses = DownloadStatusIndex.shared
    private var manager: DownloadManager { .shared }

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
                Label(item.status == .pending ? String(localized: "Queued · Pause") : String(localized: "Downloading · Pause"),
                      systemImage: "pause.circle")
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

/// Each download's status, republished only when a download is added, removed or changes
/// status — never for progress — so menus can follow downloads without blinking.
@MainActor
final class DownloadStatusIndex: ObservableObject {
    static let shared = DownloadStatusIndex()

    @Published private(set) var statuses: [String: DownloadItem.Status] = [:]
    private var subscription: AnyCancellable?

    private init() {
        subscription = DownloadManager.shared.$items
            .map { Dictionary($0.map { ($0.id, $0.status) }, uniquingKeysWith: { _, last in last }) }
            .removeDuplicates()
            .sink { [weak self] in self?.statuses = $0 }
    }
}
#endif
