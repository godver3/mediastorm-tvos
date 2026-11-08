#if os(iOS)
import SwiftUI

/// An unmatched library show's episodes (a show the server couldn't match, so it has no
/// details page): a season picker over a list of episodes. Tapping one plays its best copy
/// (Resume / Start Over when it was left partway), with the episodes after it as Up Next.
struct MobileLibraryShowView: View {
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
        List {
            Section {
                header.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if group != nil, let season = currentSeason {
                Section {
                    ForEach(season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }, id: \.episodeNumber) { episode in
                        row(episode, in: season)
                    }
                } header: {
                    if seasons.count > 1 {
                        Picker("Season", selection: Binding(get: { currentSeason?.seasonNumber ?? 0 },
                                                            set: { selectedSeason = $0 })) {
                            ForEach(seasons, id: \.seasonNumber) { Text(seasonName($0)).tag($0.seasonNumber) }
                        }
                        .pickerStyle(.menu)
                        .textCase(nil)
                    } else {
                        Text(seasonName(season))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if group == nil {
                if let loadError {
                    ContentUnavailableView {
                        Label("Couldn't Load Episodes", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try Again") { Task { await load() } }.buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle(entry.group.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(entry.group.title,
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            titleVisibility: .visible, presenting: pending) { pending in
            Button("Resume from \(pending.resumeAt.label)") { pending.start.play(from: pending.resumeAt) }
            Button("Start Over") { pending.start.play(from: nil) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    RemoteImage(url: Artwork.url(entry.group.backdropURL), size: geo.size) { _ in Rectangle().fill(.quaternary) }
                }
            }
            .overlay { LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.group.title).font(.title2.bold()).lineLimit(2)
                    Text("\(LibrarySource(entry.library.sourceType).label) · \(entry.library.name)")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ episode: LibraryEpisode, in season: LibrarySeason) -> some View {
        Button { play(episode, in: season) } label: {
            HStack(spacing: 12) {
                RemoteImage(url: Artwork.url(episode.episodeImage?.url ?? entry.group.backdropURL, size: "w300"),
                            size: CGSize(width: 120, height: 68)) { _ in Rectangle().fill(.quaternary) }
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        if preparing == key(season, episode) { ProgressView() } else {
                            Image(systemName: "play.fill").font(.caption).foregroundStyle(.white)
                                .padding(6).background(.black.opacity(0.5), in: Circle())
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(episode.episodeNumber). \(name(episode))").font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let overview = episode.episodeOverview, !overview.isEmpty {
                        Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(preparing != nil)
    }

    private func seasonName(_ season: LibrarySeason) -> String {
        season.seasonNumber == 0 ? String(localized: "Specials") : String(localized: "Season \(season.seasonNumber)")
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
        loadError = nil
        do {
            let loaded = try await APIClient.shared.libraryGroup(entry)
            group = loaded
            versions = LibraryVersions(group: loaded, libraryName: entry.library.name)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
#endif
