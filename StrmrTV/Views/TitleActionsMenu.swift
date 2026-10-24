import SwiftUI

/// A title card's long-press actions, in the Expo TV menu's order: Hide from Continue
/// Watching and Set Aside (Continue Watching titles), Remove from Set Aside, Manage Lists…,
/// the watchlist toggle, Hide from This Profile (Unhide once hidden), Mark as Watched /
/// Unwatched (movies; a card's one episode), the bulk watch-state dialogs (series), then a
/// list's own remove.
struct TitleActionsMenu: View {
    @EnvironmentObject private var titles: TitleStateStore
    let target: DetailsTarget
    /// The one episode the card stands for (Continue Watching, the calendar).
    var episode: CardEpisode?
    /// Set by a Continue Watching row, which takes the card out with its own focus handling.
    var onHideFromContinueWatching: (() -> Void)?
    /// Set in a custom list's grid.
    var onRemoveFromList: (() -> Void)?

    var body: some View {
        let setAside = titles.setAsideItem(target) != nil
        if onHideFromContinueWatching != nil || titles.inContinueWatching(target) {
            Button {
                if let onHideFromContinueWatching {
                    // The row drops the card and tells the server itself; the toast is the store's.
                    onHideFromContinueWatching()
                    titles.log.notice("hid \(target.titleID) from Continue Watching (row)")
                    titles.show(toast: String(localized: "Removed from Continue Watching"))
                } else {
                    run { await $0.hideFromContinueWatching(target) }
                }
            } label: {
                Label("Hide from Continue Watching", systemImage: "eye.slash")
            }
            if !setAside {
                Button { run { await $0.addToSetAside(target) } } label: { Label("Set Aside", systemImage: "bookmark") }
            }
        }
        if setAside {
            Button { run { await $0.removeFromSetAside(target) } } label: {
                Label("Remove from Set Aside", systemImage: "bookmark.slash")
            }
        }
        AddToListMenuButton(target: target)
        WatchlistMenuButton(target: target)
        if titles.isHidden(target) {
            Button { run { await $0.unhide(target) } } label: { Label("Unhide", systemImage: "eye") }
        } else {
            Button(role: .destructive) { run { await $0.hide(target) } } label: {
                Label("Hide from This Profile", systemImage: "eye.slash.circle")
            }
        }
        if target.isMovie {
            let watched = titles.isWatched(movie: target)
            Button { run { await $0.setWatched(!watched, movie: target) } } label: {
                Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                      systemImage: watched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
            }
        } else {
            if let episode {
                let watched = titles.isWatched(episode, of: target)
                Button { run { await $0.setWatched(!watched, episode: episode, of: target) } } label: {
                    Label(watched ? "Mark \(episode.code) as Unwatched" : "Mark \(episode.code) as Watched",
                          systemImage: watched ? "checkmark.circle.badge.xmark" : "checkmark.circle")
                }
            }
            Button { titles.watchStateTarget = target } label: {
                Label("Bulk Mark as Watched…", systemImage: "checklist")
            }
        }
        if let onRemoveFromList {
            Button(role: .destructive, action: onRemoveFromList) {
                Label("Remove from This List", systemImage: "minus.circle")
            }
        }
    }

    /// The menu closes on the press; the action runs after.
    private func run(_ action: @escaping (TitleStateStore) async -> Void) {
        let titles = titles
        Task { await action(titles) }
    }
}

/// The store's toast, centred near the bottom over the tabs (above the bottom safe area).
struct TitleToast: View {
    @EnvironmentObject private var titles: TitleStateStore

    var body: some View {
        VStack {
            Spacer()
            if let text = titles.toast {
                Label(text, systemImage: "checkmark.circle")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
                    .accessibilityIdentifier("titleToast")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
        .animation(.easeOut(duration: 0.2), value: titles.toast)
        .allowsHitTesting(false)
    }
}
