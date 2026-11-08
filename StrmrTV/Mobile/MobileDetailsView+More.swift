#if os(iOS)
import SwiftUI

/// The navigation bar's More menu: the Expo phone page's More Options (Shuffle, Set Aside,
/// Continue Watching, Episode Order, Hide from This Profile) plus the actions the TV page also
/// lists there (Audio & Subtitles, Choose Source).
extension MobileDetailsView {
    var moreMenu: some View {
        Menu {
            if !target.isMovie, !model.seasons.isEmpty {
                Section {
                    Button { model.shuffle(season: nil) } label: { Label("Shuffle Show", systemImage: "shuffle") }
                    if let season = model.currentSeason {
                        Button { model.shuffle(season: season) } label: {
                            Label("Shuffle \(WatchStateSeasons.name(season))", systemImage: "shuffle")
                        }
                    }
                }
            }
            Section {
                if model.warmPrequeue?.status != nil {
                    Button { model.showTracks() } label: { Label("Audio & Subtitles", systemImage: "waveform") }
                }
                Button { model.chooseSource(for: model.activeEpisode) } label: {
                    Label("Choose Source", systemImage: "magnifyingglass")
                }
                .disabled(!target.isMovie && model.activeEpisode == nil)
            }
            titleStateItems
            orderingMenu
        } label: {
            Label("More Options", systemImage: "ellipsis")
        }
        .accessibilityLabel("More Options")
    }

    /// Set Aside / Hide from Continue Watching (titles in Continue Watching), Remove from Set
    /// Aside, and Hide from This Profile (which leaves the page) or Unhide.
    @ViewBuilder
    private var titleStateItems: some View {
        let setAside = titles.setAsideItem(target) != nil
        Section {
            if titles.inContinueWatching(target) {
                if !setAside {
                    Button { Task { await titles.addToSetAside(target) } } label: {
                        Label("Set Aside", systemImage: "bookmark")
                    }
                }
                Button { Task { await titles.hideFromContinueWatching(target) } } label: {
                    Label("Hide from Continue Watching", systemImage: "eye.slash")
                }
            }
            if setAside {
                Button { Task { await titles.removeFromSetAside(target) } } label: {
                    Label("Remove from Set Aside", systemImage: "bookmark.slash")
                }
            }
            if titles.isHidden(target) {
                Button { Task { await titles.unhide(target) } } label: { Label("Unhide", systemImage: "eye") }
            } else {
                Button(role: .destructive) {
                    Task {
                        await titles.hide(target)
                        if titles.isHidden(target) { dismiss() }
                    }
                } label: {
                    Label("Hide from This Profile", systemImage: "eye.slash.circle")
                }
            }
        }
    }

    /// Episode Order: series with more than one ordering. A non-default one pauses Trakt /
    /// Simkl sync for the show, as the section header says.
    @ViewBuilder
    private var orderingMenu: some View {
        if model.offersOrderings {
            Menu {
                Section {
                    ForEach(model.orderings) { ordering in
                        Button { model.pickOrdering(ordering) } label: {
                            if ordering.type == model.activeOrderingEntry?.type {
                                Label(model.orderingLabel(ordering), systemImage: "checkmark")
                            } else {
                                Text(model.orderingLabel(ordering))
                            }
                        }
                    }
                } header: {
                    Text("Non-default orders pause watch-history sync for this show.")
                }
            } label: {
                Label("Episode Order: \(model.activeOrderingName)", systemImage: "list.number")
            }
        }
    }
}

/// The page's sheets and prompts: Choose Source, Versions, the prequeue's Audio & Subtitles,
/// and Resume / Start Over after a manual pick.
struct MobileDetailsPresentations: ViewModifier {
    @ObservedObject var model: MobileDetailsModel

    private func heading(_ episode: Episode?) -> String {
        episode.map { "\(model.target.name) · \($0.code)" } ?? model.target.name
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.sourcePicker) { picker in
                MobileSourcePicker(title: model.target, episode: picker.episode, heading: heading(picker.episode),
                                   libraryVersions: model.libraryVersions(for: picker.episode),
                                   contentPreference: model.contentPreference,
                                   onPickLibrary: { model.pickVersion($0, episode: picker.episode) }) { source, tracks in
                    model.choose(source, tracks: tracks, episode: picker.episode)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $model.versionsPicker) { picker in
                MobileVersionsSheet(heading: heading(picker.episode), versions: model.libraryVersions(for: picker.episode),
                                    onStream: picker.play == nil ? nil : {
                                        model.streamInstead(picker.episode, from: picker.play?.start)
                                    }) { version in
                    model.pickVersion(version, episode: picker.episode, play: picker.play)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $model.showsPrequeueTracks) { prequeueTracks }
            .confirmationDialog(heading(model.pendingSource?.episode),
                                isPresented: Binding(get: { model.pendingSource != nil },
                                                     set: { if !$0 { model.pendingSource = nil } }),
                                titleVisibility: .visible, presenting: model.pendingSource) { pending in
                Button("Resume from \(pending.resumeAt.label)") {
                    model.playSource(pending.source, tracks: pending.tracks, episode: pending.episode, from: pending.resumeAt)
                }
                Button("Start Over") {
                    model.playSource(pending.source, tracks: pending.tracks, episode: pending.episode, from: nil)
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(heading(model.pendingVersion?.episode),
                                isPresented: Binding(get: { model.pendingVersion != nil },
                                                     set: { if !$0 { model.pendingVersion = nil } }),
                                titleVisibility: .visible, presenting: model.pendingVersion) { pending in
                Button("Resume from \(pending.resumeAt.label)") {
                    model.playVersion(pending.version, episode: pending.episode, from: pending.resumeAt)
                }
                Button("Start Over") { model.playVersion(pending.version, episode: pending.episode, from: nil) }
                Button("Cancel", role: .cancel) {}
            }
    }

    /// The prequeued stream's tracks; Play there starts what the primary button plays.
    @ViewBuilder
    private var prequeueTracks: some View {
        if let status = model.warmPrequeue?.status, let path = status.streamPath {
            MobileTracksView(
                model: SourceTracksModel(releaseName: status.releaseTitle ?? model.target.name, tracks: status.trackLists),
                defaults: status.trackDefaults, preferences: model.prequeueTrackPreferences,
                overrides: Binding(get: { model.currentPrequeueOverrides }, set: { model.prequeueOverrides = (path, $0) }),
                playLabel: model.primaryTarget?.label ?? String(localized: "Play"),
                inSheet: true
            ) { _ in
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    model.playPrimary()
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}
#endif
