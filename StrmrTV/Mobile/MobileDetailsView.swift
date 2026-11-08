#if os(iOS)
import SwiftUI

/// A title's page on a phone: backdrop and logo, Play / Resume, the overview, and for series
/// a season picker over the episode list (tap an episode to play it). Loads the same
/// `/details-bundle` as the TV page and plays through the shared `PlaybackCoordinator`.
struct MobileDetailsView: View {
    let target: DetailsTarget

    @ObservedObject private var playback = PlaybackCoordinator.shared
    @State private var title: Title?
    @State private var seasons: [Season] = []
    @State private var selectedSeason: Int?
    @State private var upNext: EpisodeRef?
    @State private var primaryEpisode: Episode?
    @State private var resume: ResumeState?
    @State private var loadError: String?
    @State private var artSeed = UInt64.random(in: .min ... .max)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    meta
                    playButtons
                    if let overview = title?.overview ?? target.overview, !overview.isEmpty {
                        Text(overview).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let loadError { Text(loadError).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, 16)
                if !target.isMovie { episodesSection }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
        .onAppear { playback.prewarm(target) }
        .onChange(of: playback.sessionsEnded) { Task { await load() } }
    }

    // MARK: Header

    private var header: some View {
        GeometryReader { geo in
            RemoteImage(url: Artwork.url(title?.backdrop?.url ?? target.backdropURL), size: geo.size) { _ in
                Color.white.opacity(0.06)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, Color.brandBackground], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                Group {
                    if let logo = Artwork.logoURL(title?.logo?.url ?? target.logoURL, size: "w500") {
                        RemoteImage(url: logo, size: CGSize(width: 240, height: 80), contentMode: .fit,
                                    alignment: .bottomLeading) { _ in nameText }
                            .frame(width: 240, height: 80, alignment: .bottomLeading)
                    } else {
                        nameText
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
    }

    private var nameText: some View {
        Text(title?.name ?? target.name).font(.largeTitle.bold()).lineLimit(2)
    }

    private var meta: some View {
        let regular = seasons.filter { $0.number > 0 }.count
        let length = target.isMovie
            ? formatRuntime(title?.runtimeMinutes)
            : regular == 0 ? nil : regular == 1 ? String(localized: "1 Season") : String(localized: "\(regular) Seasons")
        let parts: [String] = [
            (title?.year ?? target.year).map(String.init),
            title?.certification,
            length,
            title?.genres?.prefix(2).joined(separator: ", "),
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return Text(parts.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
    }

    // MARK: Play

    private var primary: (episode: Episode?, start: StartPoint?, label: String)? {
        if target.isMovie {
            if let start = resumePoint(nil) { return (nil, start, String(localized: "Resume")) }
            return (nil, nil, String(localized: "Play"))
        }
        guard let ep = primaryEpisode else { return nil }
        if let start = resumePoint(ep) { return (ep, start, String(localized: "Resume \(ep.code)")) }
        return (ep, nil, String(localized: "Play \(ep.code)"))
    }

    private var playButtons: some View {
        HStack(spacing: 10) {
            Button {
                if let primary { play(primary.episode, from: primary.start) }
            } label: {
                Label(primary?.label ?? String(localized: "Play"), systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(primary == nil || title == nil)

            if let primary, primary.start != nil {
                Button { play(primary.episode, from: nil) } label: {
                    Image(systemName: "arrow.counterclockwise").font(.headline).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Start Over")
            }
        }
    }

    private func play(_ episode: Episode?, from start: StartPoint?) {
        playback.play(request(episode, from: start))
    }

    // MARK: Episodes

    private var visibleSeasons: [Season] {
        seasons.filter { $0.number > 0 } + seasons.filter { $0.number == 0 }
    }

    private var currentSeason: Season? {
        visibleSeasons.first { $0.number == selectedSeason } ?? visibleSeasons.first
    }

    @ViewBuilder
    private var episodesSection: some View {
        if !visibleSeasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    Picker("Season", selection: Binding(get: { currentSeason?.number ?? 0 }, set: { selectedSeason = $0 })) {
                        ForEach(visibleSeasons) { Text($0.name).tag($0.number) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentSeason?.name ?? "").font(.title3.weight(.semibold))
                        Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)

                LazyVStack(spacing: 14) {
                    ForEach(currentSeason?.episodes ?? []) { ep in
                        Button { play(ep, from: resumePoint(ep)) } label: { MobileEpisodeRow(episode: ep, progress: progress(ep)) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Loading and resume (as the TV page's `load` / `resumePoint`)

    private func load() async {
        do {
            let bundle = try await APIClient.shared.detailsBundle(target)
            if target.isMovie {
                guard let movie = bundle.movieDetails else { throw APIError.notReady("Details unavailable") }
                title = movie
            } else {
                guard let details = bundle.seriesDetails else { throw APIError.notReady("Details unavailable") }
                title = details.title
                seasons = details.seasons
                upNext = bundle.upNextEpisode
                primaryEpisode = DetailsView.findPrimaryEpisode(in: details.seasons, upNext: bundle.upNextEpisode)
                if selectedSeason == nil { selectedSeason = primaryEpisode?.seasonNumber }
            }
            resume = bundle.resume
            loadError = nil
        } catch {
            if title == nil { loadError = error.localizedDescription }
        }
    }

    private func resumePoint(_ episode: Episode?) -> StartPoint? {
        guard let episode else { return resume?.startPoint }
        if let own = episode.resume { return own.startPoint }
        if let upNext, DetailsView.isUpNext(episode, upNext) { return resume?.startPoint }
        return nil
    }

    private func progress(_ episode: Episode) -> Double {
        if let own = episode.resume { return own.eligible ? own.fraction : 0 }
        if let upNext, DetailsView.isUpNext(episode, upNext), resume?.eligible == true { return resume?.fraction ?? 0 }
        return 0
    }

    private func request(_ episode: Episode?, from start: StartPoint?) -> PlaybackRequest {
        PlaybackRequest(title: target, episode: episode.map(Self.episodeInfo), start: start,
                        following: episode.map(airedEpisodes(after:)) ?? [],
                        artwork: .init(
                            backdropURLs: PlaybackRequest.Artwork.rotation(
                                still: episode?.image?.url,
                                primary: title?.backdrop?.url ?? target.backdropURL,
                                alternates: title?.backdrops?.map(\.url) ?? [],
                                showing: title?.backdrop?.url ?? target.backdropURL,
                                seed: artSeed),
                            logoURL: title?.logo?.url))
    }

    private static func episodeInfo(_ ep: Episode) -> PlaybackRequest.EpisodeInfo {
        PlaybackRequest.EpisodeInfo(season: ep.seasonNumber, episode: ep.episodeNumber,
                                    absolute: ep.absoluteEpisodeNumber, name: ep.name, itemID: ep.itemId,
                                    imageURL: ep.image?.url, overview: ep.overview, numbering: ep.numbering)
    }

    private func airedEpisodes(after episode: Episode) -> [PlaybackRequest.EpisodeInfo] {
        let regular = seasons.filter { $0.number > 0 }.sorted { $0.number < $1.number }.flatMap(\.episodes)
        guard let index = regular.firstIndex(where: { $0.id == episode.id }) else { return [] }
        return regular[(index + 1)...]
            .prefix { ReleaseBadge.forEpisode(airDate: $0.airedDate) == nil }
            .map(Self.episodeInfo)
    }
}

private struct MobileEpisodeRow: View {
    let episode: Episode
    let progress: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: Artwork.url(episode.image?.url, size: "w300"), size: CGSize(width: 140, height: 79)) { _ in
                Color.white.opacity(0.08)
            }
            .frame(width: 140, height: 79)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                Image(systemName: "play.fill").font(.footnote).padding(8)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .overlay(alignment: .bottom) {
                if progress > 0 { MobileProgressBar(value: progress).padding(.horizontal, 6).padding(.bottom, 5) }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(episode.episodeNumber). \(episode.name)").font(.subheadline.weight(.semibold)).lineLimit(2)
                    if episode.watched == true {
                        Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let runtime = formatRuntime(episode.runtimeMinutes) {
                    Text(runtime).font(.caption).foregroundStyle(.secondary)
                }
                if let overview = episode.overview {
                    Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
#endif
