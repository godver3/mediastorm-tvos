import SwiftUI

extension DetailsView {
    /// Any of the page's menus is up: the source picker (or its Resume / Start Over prompt), Add
    /// to List…, the series watch-state screen, Audio & Subtitles, or More Options. The backdrop trailer stops for
    /// the visit when one opens (`DetailsTrailerModifier`), from this one place.
    var menuOpen: Bool {
        sourcePicker != nil || pendingSource != nil || showWatchState || showPrequeueTracks || showMore
            || customLists.picking != nil
    }

    /// The Expo details page's "more options" titles actions: Set Aside and Hide from
    /// Continue Watching (titles in Continue Watching), Remove from Set Aside, and Hide from
    /// This Profile (which, as there, leaves the page) or Unhide. The states match the
    /// long-press menu's (`TitleActionsMenu`), from the same store.
    ///
    /// A button and a dialog rather than a `Menu`: a menu's focus doesn't reach `$focus`, so
    /// a reload while it was focused moved focus to Play under the next Select.
    var moreMenu: some View {
        Button { showMore = true } label: {
            Label("More Options", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .focused($focus, equals: .action(.more))
        .confirmationDialog(target.name, isPresented: $showMore, titleVisibility: .visible) {
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
            Button("Cancel", role: .cancel) {}
        }
    }
}
