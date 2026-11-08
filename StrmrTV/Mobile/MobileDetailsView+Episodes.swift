#if os(iOS)
import SwiftUI

/// Series: the Expo phone carousel. Season chips (with episode counts; long press marks a
/// season) over a horizontal row of episode cards. Tapping a card selects it as what Play
/// targets; tapping the selected card plays it. Long press lists the episode's actions.
extension MobileDetailsView {
    @ViewBuilder
    var episodesSection: some View {
        if !model.visibleSeasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                seasonChips
                if let season = model.currentSeason {
                    episodeCarousel(season).id(season.id)
                }
            }
        } else if model.title == nil, model.loadError == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
        }
    }

    private var seasonChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.visibleSeasons) { season in
                        let selected = season.number == model.currentSeason?.number
                        Button {
                            model.selectedSeason = season.number
                        } label: {
                            HStack(spacing: 6) {
                                Text(WatchStateSeasons.name(season))
                                Text("\(season.episodes.count)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background((selected ? Color.black : Color.white).opacity(0.15), in: Capsule())
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .foregroundStyle(selected ? .black : .white)
                            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.12)))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .contextMenu { seasonToggle(season, dismissesMenu: true) }
                        .id(season.number)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
            // Opens on the selected season (up next's), however far along the row it is.
            .onAppear {
                if let number = model.currentSeason?.number { proxy.scrollTo(number, anchor: .center) }
            }
            .onChange(of: model.selectedSeason) { _, number in
                if let number { withAnimation { proxy.scrollTo(number, anchor: .center) } }
            }
        }
    }

    private func episodeCarousel(_ season: Season) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(season.episodes) { ep in episodeCard(ep).id(ep.id) }
                }
                .padding(.horizontal, 16)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
            .onAppear {
                if let id = model.activeEpisode?.id, season.episodes.contains(where: { $0.id == id }),
                   id != season.episodes.first?.id {
                    proxy.scrollTo(id, anchor: .leading)
                }
            }
        }
    }

    private func episodeCard(_ ep: Episode) -> some View {
        let watched = model.isWatched(ep)
        let selected = ep.id == model.activeEpisode?.id
        return Button {
            if selected { model.play(ep, from: model.resumePoint(ep)) } else { model.selectedEpisodeID = ep.id }
        } label: {
            MobileEpisodeCard(
                episode: ep, watched: watched, selected: selected, progress: model.progress(ep),
                inLibrary: !model.libraryVersions(for: ep).isEmpty,
                hidesThumbnail: spoilers.hides(.thumbnail, of: ep, current: model.primaryEpisode, watched: watched),
                hidesOverview: spoilers.hides(.overview, of: ep, current: model.primaryEpisode, watched: watched),
                fallbackImage: model.backdropURL)
        }
        .buttonStyle(.plain)
        .accessibilityHint(selected ? "Plays this episode" : "Selects this episode")
        .contextMenu {
            let resumeAt = model.resumePoint(ep)
            Button { model.play(ep, from: resumeAt) } label: {
                Label(resumeAt.map { "Resume from \($0.label)" } ?? String(localized: "Play"), systemImage: "play.fill")
            }
            if resumeAt != nil {
                Button { model.play(ep, from: nil) } label: { Label("Start Over", systemImage: "arrow.counterclockwise") }
            }
            if !model.libraryVersions(for: ep).isEmpty {
                Button { model.versionsPicker = .init(episode: ep) } label: {
                    Label("Choose Version", systemImage: "externaldrive")
                }
            }
            Button { model.chooseSource(for: ep) } label: { Label("Choose Source", systemImage: "magnifyingglass") }
            episodeDownloadItem(ep)
            Button { model.toggleWatched(ep, titles: titles) } label: {
                Label(watched ? "Mark as Unwatched" : "Mark as Watched", systemImage: watched ? "eye.slash" : "eye")
            }
        }
    }
}

/// One episode in the carousel: the still with its number, progress / watched / unreleased
/// badge and progress bar, then the name, overview and runtime · air date.
struct MobileEpisodeCard: View {
    let episode: Episode
    let watched: Bool
    let selected: Bool
    let progress: Double
    let inLibrary: Bool
    let hidesThumbnail: Bool
    let hidesOverview: Bool
    let fallbackImage: String?

    static let width: CGFloat = 280
    private static let imageSize = CGSize(width: width, height: width * 9 / 16)

    private var unreleased: String? { ReleaseBadge.forEpisode(airDate: episode.airedDate) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: Artwork.url(episode.image?.url ?? fallbackImage, size: "w500"), size: Self.imageSize) { _ in
                Rectangle().fill(.white.opacity(0.08))
                    .overlay(Image(systemName: "film").font(.title2).foregroundStyle(.tertiary))
            }
            .frame(width: Self.imageSize.width, height: Self.imageSize.height)
            .blur(radius: hidesThumbnail ? 24 : 0, opaque: true)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text("\(episode.episodeNumber)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) { statusBadge.padding(8) }
            .overlay(alignment: .bottomTrailing) {
                if inLibrary {
                    Image(systemName: "externaldrive.fill").font(.caption2.weight(.bold))
                        .padding(5).background(.black.opacity(0.7), in: Circle())
                        .padding(.trailing, 8).padding(.bottom, progress > 0 ? 16 : 8)
                        .accessibilityLabel("In your library")
                }
            }
            .overlay(alignment: .bottom) {
                if progress > 0 { MobileProgressBar(value: progress).padding(.horizontal, 8).padding(.bottom, 6) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.white : .clear, lineWidth: 2)
            }

            Text(episode.name.isEmpty ? String(localized: "Episode \(episode.episodeNumber)") : episode.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(watched ? .secondary : .primary)
                .lineLimit(2)
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .blur(radius: hidesOverview ? 5 : 0)
                    .accessibilityHidden(hidesOverview)
            }
            if !meta.isEmpty {
                Text(meta).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var statusBadge: some View {
        if progress > 0 {
            Text("\(Int((progress * 100).rounded()))%")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.7), in: Capsule())
        } else if watched {
            Image(systemName: "checkmark").font(.caption2.weight(.heavy))
                .padding(5).background(Color.accentColor, in: Circle())
                .accessibilityLabel("Watched")
        } else if let unreleased {
            Label(unreleased, systemImage: "clock").font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .foregroundStyle(.black)
                .background(.white, in: Capsule())
        }
    }

    private var meta: String {
        [formatRuntime(episode.runtimeMinutes), EpisodeCard.airDateText(episode.airedDate)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
#endif
