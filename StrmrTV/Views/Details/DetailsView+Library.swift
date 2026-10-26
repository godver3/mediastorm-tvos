import SwiftUI

/// The title's copies in the profile's local, Plex and Jellyfin libraries. Play uses the best
/// copy of the movie or episode when there is one (local first, by user decision); Versions
/// lists every copy, and Choose Source still searches for streams.
extension DetailsView {
    struct VersionsTarget: Identifiable {
        let episode: Episode?
        var id: String { episode?.id ?? "movie" }
    }

    /// A copy picked in Versions, waiting on the Resume / Start Over choice.
    struct PendingVersion {
        let version: LibraryVersion
        let episode: Episode?
        let resumeAt: StartPoint
    }

    /// Looks the title up in the libraries once per page (not on every reload after playback).
    func startLibraryLookup() {
        guard libraryLookup == nil else { return }
        let target = target
        let lookup = Task { () -> LibraryVersions? in
            guard let matches = try? await APIClient.shared.libraryMatches(for: target) else { return nil }
            let versions = LibraryVersions(matches: matches)
            return versions.isEmpty ? nil : versions
        }
        libraryLookup = lookup
        Task { libraryVersions = await lookup.value }
    }

    /// The copies of a movie (no episode) or of one episode, best first.
    func libraryVersions(for episode: Episode?) -> [LibraryVersion] {
        guard let libraryVersions else { return [] }
        guard let episode else { return target.isMovie ? libraryVersions.movie : [] }
        return libraryVersions.versions(season: episode.seasonNumber, episode: episode.episodeNumber)
    }

    /// The copies of what the primary button plays.
    var primaryVersions: [LibraryVersion] {
        libraryVersions(for: target.isMovie ? nil : primaryEpisode)
    }

    /// Play, through the library when it has the movie or episode. A press while the lookup is
    /// still running waits for it, so a library title never starts a search by mistake.
    func playPreferringLibrary(_ episode: Episode?, from start: StartPoint?) {
        guard libraryVersions == nil, let lookup = libraryLookup else {
            return playback.play(request(episode, from: start), picks: prequeuePick)
        }
        Task {
            var request = request(episode, from: start)
            request.library = await lookup.value
            playback.play(request, picks: prequeuePick)
        }
    }

    /// Icon-only like Choose Source. Focused, its caption names the copy Play uses.
    @ViewBuilder
    var versionsButton: some View {
        let versions = primaryVersions
        if let best = versions.first {
            Button { versionsPicker = VersionsTarget(episode: target.isMovie ? nil : primaryEpisode) } label: {
                Label("Versions", systemImage: "externaldrive").labelStyle(.iconOnly)
            }
            .focused($focus, equals: .action(.versions))
            .focusCaption(versions.count == 1
                              ? "\(best.source.label) · \(best.quality)"
                              : String(localized: "\(versions.count) versions · \(best.source.label) · \(best.quality)"),
                          shown: focus == .action(.versions))
        }
    }

    /// A copy picked in Versions: offer Resume / Start Over when there is a resume point. Both
    /// wait for the list's dismissal: a library file resolves fast enough that the player could
    /// otherwise be presented over a cover still going away.
    func pickVersion(_ version: LibraryVersion, episode: Episode?) {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            if let resumeAt = resumePoint(episode) {
                pendingVersion = PendingVersion(version: version, episode: episode, resumeAt: resumeAt)
            } else {
                playVersion(version, episode: episode, from: nil)
            }
        }
    }

    func playVersion(_ version: LibraryVersion, episode: Episode?, from start: StartPoint?) {
        playback.playLibrary(request(episode, from: start), version: version)
    }

    var libraryVersionsPresentation: LibraryVersionsPresentation {
        LibraryVersionsPresentation(
            title: target, backdropURL: title?.backdrop?.url ?? target.backdropURL,
            picker: $versionsPicker, pending: $pendingVersion,
            versions: { libraryVersions(for: $0) },
            onPick: { pickVersion($0, episode: $1) },
            onPlay: { pending, start in playVersion(pending.version, episode: pending.episode, from: start) })
    }
}

/// The Versions list over the details page, and the Resume / Start Over choice after a pick.
struct LibraryVersionsPresentation: ViewModifier {
    let title: DetailsTarget
    let backdropURL: String?
    @Binding var picker: DetailsView.VersionsTarget?
    @Binding var pending: DetailsView.PendingVersion?
    let versions: (Episode?) -> [LibraryVersion]
    let onPick: (LibraryVersion, Episode?) -> Void
    let onPlay: (DetailsView.PendingVersion, StartPoint?) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $picker) { picker in
                LibraryVersionsView(heading: picker.episode.map { "\(title.name) · \($0.code)" } ?? title.name,
                                    versions: versions(picker.episode), backdropURL: backdropURL) { version in
                    onPick(version, picker.episode)
                }
            }
            .confirmationDialog(
                pending.map { pending in pending.episode.map { "\(title.name) · \($0.code)" } ?? title.name } ?? "",
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible,
                presenting: pending
            ) { pending in
                Button("Resume from \(pending.resumeAt.label)") { onPlay(pending, pending.resumeAt) }
                Button("Start Over") { onPlay(pending, nil) }
                Button("Cancel", role: .cancel) {}
            }
    }
}
