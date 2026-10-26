import SwiftUI

extension DetailsView {
    /// Any of the page's menus is up: the source picker (or its Resume / Start Over prompt),
    /// Audio & Subtitles, a card's Manage Lists sheet, or a menu (`systemMenuOpen`: Manage
    /// Lists, Watch State, More Options, an episode's long press). The backdrop trailer stops
    /// for the visit when one opens (`DetailsTrailerModifier`), from this one place.
    var menuOpen: Bool {
        sourcePicker != nil || pendingSource != nil || showPrequeueTracks
            || customLists.picking != nil || systemMenuOpen || customizingButtons
    }

    /// The Expo details page's "more options" titles actions, as a menu: Set Aside and Hide
    /// from Continue Watching (titles in Continue Watching), Remove from Set Aside, and Hide
    /// from This Profile (which, as there, leaves the page) or Unhide. The states match the
    /// long-press menu's (`TitleActionsMenu`), from the same store. Reloads under an open
    /// menu leave focus alone (`load`), so focus stays on it. Above them, the actions
    /// Customize Buttons moved out of the row (`movedActions`); Customize Buttons… comes last.
    var moreMenu: some View {
        Menu {
            movedActions
            let setAside = titles.setAsideItem(target) != nil
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
            Divider()
            Button { customizingButtons = true } label: {
                Label("Customize Buttons…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("More Options", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .focused($focus, equals: .action(.more))
    }

    /// The row's actions set to More, in row order, each labelled with its current state.
    @ViewBuilder
    var movedActions: some View {
        let more = buttons.inMore()
        let primary = primaryTarget
        Section {
            if more.contains(.startOver), let primary, primary.start != nil {
                Button { play(episode: primary.episode, from: nil) } label: {
                    Label("Start Over", systemImage: "arrow.counterclockwise")
                }
            }
            if more.contains(.versions), !primaryVersions.isEmpty {
                Button { versionsPicker = VersionsTarget(episode: target.isMovie ? nil : primaryEpisode) } label: {
                    Label("Versions", systemImage: "externaldrive")
                }
            }
            if more.contains(.chooseSource) {
                Button { chooseSource() } label: { Label("Choose Source", systemImage: "magnifyingglass") }
                    .disabled(!canChooseSource)
            }
            if more.contains(.tracks), warmPrequeue != nil {
                Button { showTracks() } label: { Label("Audio & Subtitles", systemImage: "waveform") }
            }
            if more.contains(.trailer), trailer.available {
                Button { trailer.buttonPressed() } label: {
                    Label(trailerPlaying ? "Pause Trailer" : "Play Trailer",
                          systemImage: trailerPlaying ? "pause.fill" : "film")
                }
            }
            if more.contains(.watchlist) {
                Button { Task { await toggleWatchlist() } } label: {
                    Label(inWatchlist ? "Remove from Watchlist" : "Add to Watchlist",
                          systemImage: inWatchlist ? "minus" : "plus")
                }
            }
            if more.contains(.lists) {
                // The card long press's Manage Lists sheet: a menu inside this one can't keep
                // `DetailsListsMenu`'s memberships load or New List alert.
                Button { customLists.picking = target } label: {
                    Label("Manage Lists…", systemImage: "text.badge.checkmark")
                }
            }
            if more.contains(.watched) {
                if target.isMovie {
                    let watched = movieWatched == true
                    Button { Task { await toggleMovieWatched() } } label: {
                        Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                              systemImage: watched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
                    }
                } else if !seasons.isEmpty {
                    Menu { watchStateItems } label: { Label("Watch State", systemImage: "eye") }
                }
            }
        }
    }
}
