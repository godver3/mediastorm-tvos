import SwiftUI

extension DetailsView {
    /// Any of the page's menus is up: the source picker (or its Resume / Start Over prompt),
    /// Audio & Subtitles, a card's Manage Lists sheet, or a menu (`systemMenuOpen`: Manage
    /// Lists, Watch State, More Options, an episode's long press). The backdrop trailer stops
    /// for the visit when one opens (`DetailsTrailerModifier`), from this one place.
    var menuOpen: Bool {
        sourcePicker != nil || pendingSource != nil || showPrequeueTracks
            || customLists.picking != nil || systemMenuOpen
    }

    /// The Expo details page's "more options" titles actions, as a menu: Set Aside and Hide
    /// from Continue Watching (titles in Continue Watching), Remove from Set Aside, and Hide
    /// from This Profile (which, as there, leaves the page) or Unhide. The states match the
    /// long-press menu's (`TitleActionsMenu`), from the same store. Reloads under an open
    /// menu leave focus alone (`load`), so focus stays on it.
    var moreMenu: some View {
        Menu {
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
        } label: {
            Label("More Options", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .focused($focus, equals: .action(.more))
    }
}
