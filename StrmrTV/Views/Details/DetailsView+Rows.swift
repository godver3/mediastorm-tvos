import SwiftUI

extension DetailsView {
    // MARK: Episodes

    var episodesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if visibleSeasons.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 20) {
                        ForEach(visibleSeasons) { season in
                            Button(season.number == 0 ? "Specials" : "Season \(season.number)") {
                                selectedSeason = season.number
                            }
                            .buttonStyle(SeasonChipStyle(selected: season.number == currentSeason?.number))
                            .focused($focus, equals: .season(season.number))
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
                // Full-width section: Up from an episode right of the last chip still lands here.
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                .defaultFocus($focus, entry(.seasons), priority: .userInitiated)
            } else {
                Text(currentSeason?.name ?? "Episodes").font(.headline)
            }

            if let season = currentSeason {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 40) {
                            ForEach(season.episodes) { ep in
                                EpisodeCard(
                                    episode: ep,
                                    focus: $focus,
                                    watched: isWatched(ep),
                                    hidesThumbnail: spoilers.hides(.thumbnail, of: ep, current: primaryEpisode,
                                                                   watched: isWatched(ep)),
                                    hidesOverview: spoilers.hides(.overview, of: ep, current: primaryEpisode,
                                                                  watched: isWatched(ep)),
                                    fallbackImage: title?.backdrop?.url ?? target.backdropURL,
                                    onChooseSource: { sourcePicker = SourcePickerTarget(episode: ep) },
                                    onToggleWatched: { toggleWatched(ep) },
                                    inLibrary: !libraryVersions(for: ep).isEmpty,
                                    onChooseVersion: libraryVersions(for: ep).isEmpty ? nil
                                        : { versionsPicker = VersionsTarget(episode: ep) }
                                ) {
                                    play(episode: ep, from: resumePoint(ep))
                                }
                                .id(ep.id)
                            }
                        }
                        .padding(.vertical, 30)
                    }
                    // Full width with the page inset inside, so the lazy row keeps cards that are
                    // still visible in the margin (see the Home row).
                    .contentMargins(.horizontal, 80, for: .scrollContent)
                    .padding(.horizontal, -80)
                    .scrollClipDisabled()
                    .focusSection()
                    .defaultFocus($focus, entry(.episodes), priority: .userInitiated)
                    // The entry episode may be far along a lazy row: bring it on screen so it
                    // exists to take focus.
                    .onAppear {
                        if let id = episodeEntry(season), id != season.episodes.first?.id {
                            proxy.scrollTo(id, anchor: .leading)
                        }
                    }
                }
                .id(season.id)
            }
        }
    }

    // MARK: Related rows

    var isKids: Bool { AppSession.shared.profile?.isKidsProfile == true }

    /// The top-billed cast, as many as the Expo TV row shows.
    var cast: [CastMember] {
        var seen = Set<Int>()
        return (title?.credits?.cast ?? []).filter { seen.insert($0.id).inserted }.prefix(10).map { $0 }
    }

    func relatedIDs(_ row: RelatedRow) -> [String] {
        switch row {
        case .collection: collectionMovies.map(\.id)
        case .similar: similar.prefix(20).map(\.id)
        case .cast: cast.map { String($0.id) }
        }
    }

    var relatedSections: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let collection = title?.collection, !collectionMovies.isEmpty {
                relatedRow(String(localized: "Part of \(collection.name)"), .collection) {
                    ForEach(collectionMovies) { posterCard($0, in: .collection) }
                }
            }
            if !similar.isEmpty {
                relatedRow(String(localized: "More Like This"), .similar) {
                    ForEach(similar.prefix(20)) { posterCard($0, in: .similar) }
                }
            }
            if !cast.isEmpty {
                relatedRow(String(localized: "Cast"), .cast) {
                    ForEach(cast, id: \.id) { member in
                        CastCard(member: member, opens: !isKids)
                            .focused($focus, equals: .related(.cast, String(member.id)))
                    }
                }
            }
        }
    }

    func posterCard(_ title: Title, in row: RelatedRow) -> some View {
        PosterCard(title: title, width: Self.relatedCardWidth, opens: !isKids)
            .focused($focus, equals: .related(row, title.id))
    }

    static let relatedCardWidth: CGFloat = 200

    /// A titled horizontal row laid out like the episode row.
    func relatedRow<Cards: View>(_ heading: String, _ row: RelatedRow,
                                         @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(heading).font(.headline)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) { cards() }
                    .padding(.vertical, 30)
            }
            .contentMargins(.horizontal, 80, for: .scrollContent)
            .padding(.horizontal, -80)
            .scrollClipDisabled()
            .focusSection()
            .defaultFocus($focus, entry(.related(row)), priority: .userInitiated)
        }
    }
}
