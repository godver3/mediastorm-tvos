import SwiftUI

/// What selecting a library title does, around a card's artwork. A matched title opens its
/// catalog details page, which plays the library's copy. An unmatched show opens its library
/// episodes. An unmatched file (a home video) plays at once: after a choice of copies when it
/// has several, and Resume / Start Over when it was left partway.
struct LibraryEntryLink<Label: View>: View {
    let entry: LibraryEntry
    @ViewBuilder let label: Label

    @State private var choice: Choice?
    @State private var pending: Pending?
    @State private var preparing = false

    struct Choice: Identifiable {
        let group: LibraryGroup
        let versions: LibraryVersions
        var id: String { group.id }
    }

    struct Pending {
        let start: LibraryFileStart
        let resumeAt: StartPoint
    }

    var body: some View {
        if let target = entry.detailsTarget {
            NavigationLink(value: target) { label }
        } else if entry.group.isShow {
            NavigationLink(value: LibraryShowTarget(entry: entry)) { label }
        } else {
            Button { open() } label: {
                label.overlay { if preparing { ProgressView() } }
            }
            .fullScreenCover(item: $choice) { choice in
                LibraryVersionsView(heading: entry.group.title, versions: choice.versions.movie,
                                    backdropURL: entry.group.backdropURL) { version in
                    Task {
                        // Let the list's dismissal finish before a dialog or the player goes up.
                        try? await Task.sleep(for: .milliseconds(400))
                        await prepare(version, versions: choice.versions, group: choice.group)
                    }
                }
            }
            .confirmationDialog(entry.group.title,
                                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible, presenting: pending) { pending in
                Button("Resume from \(pending.resumeAt.label)") { pending.start.play(from: pending.resumeAt) }
                Button("Start Over") { pending.start.play(from: nil) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Fetches the file list (cards carry none), then plays the only copy or offers the choice.
    private func open() {
        guard !preparing else { return }
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let group = try await APIClient.shared.libraryGroup(entry)
                let versions = LibraryVersions(group: group, libraryName: entry.library.name)
                if versions.movie.count > 1 {
                    choice = Choice(group: group, versions: versions)
                } else if let version = versions.movie.first {
                    await prepare(version, versions: versions, group: group)
                } else {
                    throw APIError.notReady(String(localized: "This title has no playable file."))
                }
            } catch {
                PlaybackCoordinator.shared.errorMessage = error.localizedDescription
            }
        }
    }

    private func prepare(_ version: LibraryVersion, versions: LibraryVersions, group: LibraryGroup) async {
        do {
            let start = try await LibraryFileStart.prepare(version, versions: versions, group: group, episode: nil)
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

/// An unmatched library file ready to play: its stream path, and where it was left. Its
/// progress is keyed by that path (the Expo app's rule), since no catalog id names it.
struct LibraryFileStart {
    let group: LibraryGroup
    let versions: LibraryVersions
    let version: LibraryVersion
    let episode: PlaybackRequest.EpisodeInfo?
    var following: [PlaybackRequest.EpisodeInfo] = []
    let playback: LibraryPlaybackInfo
    let resumeAt: StartPoint?

    @MainActor
    static func prepare(_ version: LibraryVersion, versions: LibraryVersions, group: LibraryGroup,
                        episode: PlaybackRequest.EpisodeInfo?,
                        following: [PlaybackRequest.EpisodeInfo] = []) async throws -> LibraryFileStart {
        let playback = try await APIClient.shared.libraryPlayback(itemID: version.id)
        let resume = await APIClient.shared.resumeState(mediaType: episode == nil ? "movie" : "episode",
                                                        itemID: playback.streamPath)
        return LibraryFileStart(group: group, versions: versions, version: version, episode: episode,
                                following: following, playback: playback, resumeAt: resume?.startPoint)
    }

    @MainActor
    func play(from start: StartPoint?) {
        let backdrops = [episode?.imageURL, group.backdropURL].compactMap { $0 }
        let request = PlaybackRequest(title: DetailsTarget(unmatched: group), episode: episode, start: start,
                                      following: following, artwork: .init(backdropURLs: backdrops),
                                      library: versions)
        PlaybackCoordinator.shared.playLibrary(request, version: version, playback: playback)
    }
}

/// An unmatched show's library episodes, as a navigation value (`LibraryShowView`).
struct LibraryShowTarget: Hashable {
    let entry: LibraryEntry
}

/// A library title as a portrait card in a library grid.
struct LibraryPosterCard: View {
    let entry: LibraryEntry
    var width: CGFloat = PosterCard.width

    @FocusState private var isFocused: Bool

    private var height: CGFloat { width * PosterCard.height / PosterCard.width }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: height)) {
            LibraryEntryLink(entry: entry) { artwork }
                .buttonStyle(PosterFocusStyle(isFocused: isFocused))
                .focused($isFocused)
                .accessibilityLabel(entry.group.title)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.group.title).font(.caption.weight(.semibold)).lineLimit(1)
                Text(HomeCard.kindLine(year: entry.group.year, isMovie: !entry.group.isShow))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var artwork: some View {
        RemoteImage(url: Artwork.url(entry.group.posterURL, size: "w500"), size: CGSize(width: width, height: height)) { _ in
            // No poster (a home video): the title on a plain panel, as the Expo grid forces it.
            Rectangle().fill(.quaternary)
                .overlay(Text(entry.group.title).font(.caption).multilineTextAlignment(.center).padding())
        }
    }
}
