import SwiftUI

/// An unmatched show's library episodes: a show the server couldn't match, so it has no
/// catalog details page. Seasons as chips, episodes as rows; Select plays the episode's best
/// copy from where it was left, with the episodes after it as Up Next.
struct LibraryShowView: View {
    let target: LibraryShowTarget

    @State private var group: LibraryGroup?
    @State private var versions: LibraryVersions?
    @State private var selectedSeason: Int?
    @State private var loadError: String?
    @State private var pending: Pending?
    /// The episode whose stream is being looked up.
    @State private var preparing: LibraryVersions.Key?

    struct Pending {
        let start: LibraryFileStart
        let resumeAt: StartPoint
    }

    private var entry: LibraryEntry { target.entry }

    /// Real seasons first, specials last.
    private var seasons: [LibrarySeason] {
        let all = (group?.seasons ?? []).sorted { $0.seasonNumber < $1.seasonNumber }
        return all.filter { $0.seasonNumber > 0 } + all.filter { $0.seasonNumber == 0 }
    }

    private var currentSeason: LibrarySeason? {
        seasons.first { $0.seasonNumber == selectedSeason } ?? seasons.first
    }

    var body: some View {
        ZStack {
            Backdrop(url: Artwork.url(entry.group.backdropURL))
                .overlay(Color.black.opacity(0.65))
                .ignoresSafeArea()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 30) {
                    Text(entry.group.title).font(.system(size: 60, weight: .bold)).lineLimit(2)
                    Text("\(LibrarySource(entry.library.sourceType).label) · \(entry.library.name)")
                        .font(.callout).foregroundStyle(.secondary)
                    if group != nil {
                        if seasons.count > 1 { seasonChips }
                        if let season = currentSeason { episodeRows(season) }
                    } else if let loadError {
                        Text(loadError).foregroundStyle(.secondary)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: 1500, alignment: .leading)
                .padding(80)
            }
            .scrollClipDisabled()
        }
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .confirmationDialog(entry.group.title,
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { pending in
            Button("Resume from \(pending.resumeAt.label)") { pending.start.play(from: pending.resumeAt) }
            Button("Start Over") { pending.start.play(from: nil) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var seasonChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                ForEach(seasons, id: \.seasonNumber) { season in
                    Button(season.seasonNumber == 0 ? String(localized: "Specials")
                                                    : String(localized: "Season \(season.seasonNumber)")) {
                        selectedSeason = season.seasonNumber
                    }
                    .buttonStyle(SeasonChipStyle(selected: season.seasonNumber == currentSeason?.seasonNumber))
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }

    private func episodeRows(_ season: LibrarySeason) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }, id: \.episodeNumber) { episode in
                Button { play(episode, in: season) } label: {
                    HStack(spacing: 28) {
                        RemoteImage(url: Artwork.url(episode.episodeImage?.url ?? entry.group.backdropURL, size: "w300"),
                                    size: CGSize(width: 240, height: 135)) { _ in Rectangle().fill(.quaternary) }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(episode.episodeNumber). \(name(episode))").font(.callout.weight(.semibold)).lineLimit(1)
                            if let overview = episode.episodeOverview, !overview.isEmpty {
                                Text(overview).font(.caption).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if preparing == key(season, episode) { ProgressView() }
                    }
                }
                .buttonStyle(SourceRowStyle())
            }
        }
        .focusSection()
    }

    private func name(_ episode: LibraryEpisode) -> String {
        if let title = episode.episodeTitle, !title.isEmpty { return title }
        return String(localized: "Episode \(episode.episodeNumber)")
    }

    private func key(_ season: LibrarySeason, _ episode: LibraryEpisode) -> LibraryVersions.Key {
        LibraryVersions.Key(season: season.seasonNumber, episode: episode.episodeNumber)
    }

    private func info(_ season: LibrarySeason, _ episode: LibraryEpisode) -> PlaybackRequest.EpisodeInfo {
        PlaybackRequest.EpisodeInfo(season: season.seasonNumber, episode: episode.episodeNumber, absolute: nil,
                                    name: name(episode), itemID: nil, imageURL: episode.episodeImage?.url,
                                    overview: episode.episodeOverview)
    }

    /// The regular-season episodes after `episode`, in order, for Up Next.
    private func following(_ season: LibrarySeason, _ episode: LibraryEpisode) -> [PlaybackRequest.EpisodeInfo] {
        let ordered = seasons.filter { $0.seasonNumber > 0 }.flatMap { s in
            s.episodes.sorted { $0.episodeNumber < $1.episodeNumber }.map { (s, $0) }
        }
        guard let index = ordered.firstIndex(where: { $0.0.seasonNumber == season.seasonNumber
            && $0.1.episodeNumber == episode.episodeNumber }) else { return [] }
        return ordered[(index + 1)...].map { info($0.0, $0.1) }
    }

    private func play(_ episode: LibraryEpisode, in season: LibrarySeason) {
        guard preparing == nil, let group, let versions,
              let version = versions.best(season: season.seasonNumber, episode: episode.episodeNumber) else { return }
        preparing = key(season, episode)
        Task {
            defer { preparing = nil }
            do {
                let start = try await LibraryFileStart.prepare(version, versions: versions, group: group,
                                                               episode: info(season, episode),
                                                               following: following(season, episode))
                if let resumeAt = start.resumeAt {
                    pending = Pending(start: start, resumeAt: resumeAt)
                } else {
                    start.play(from: nil)
                }
            } catch {
                PlaybackCoordinator.shared.errorMessage = error.localizedDescription
            }
        }
    }

    private func load() async {
        guard group == nil else { return }
        do {
            let loaded = try await APIClient.shared.libraryGroup(entry)
            group = loaded
            versions = LibraryVersions(group: loaded, libraryName: entry.library.name)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
