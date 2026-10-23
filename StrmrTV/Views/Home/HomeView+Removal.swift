import SwiftUI

/// Cards leaving a Home row from their own context menu (Hide from Continue Watching,
/// Remove from Watchlist), with focus moved off them first.
extension HomeView {
    /// Hides a Continue Watching title.
    func hide(_ card: HomeCard) {
        remove(PendingRemoval(focus: HomeFocus(shelf: HomeShelf.continueWatchingID, card: card.id), watchlistTarget: nil))
    }

    /// Removes a title from the watchlist. Its card leaves the Watchlist row only; on any
    /// other row it stays, and focus with it.
    func removeFromWatchlist(_ target: DetailsTarget) {
        guard let card = heroFocus, card.shelf == store.watchlistShelfID, card.card == target.titleID else {
            Task { try? await watchlist.remove(target) }
            return
        }
        remove(PendingRemoval(focus: card, watchlistTarget: target))
    }

    /// The context menu is still up when its action runs, and on closing it hands focus
    /// back to the card; removing the card before that left focus nowhere (or sent it to
    /// the row's first card). So the card goes once focus is back on it, or after a
    /// second if it never comes back.
    func remove(_ pending: PendingRemoval) {
        pendingRemoval = pending
        Task {
            try? await Task.sleep(for: .seconds(1))
            if pendingRemoval == pending { completeRemoval(pending) }
        }
    }

    /// Moves focus to the card that takes the removed one's place (else the one before;
    /// for a row's last card, the row below's, else the row above's), drops the card, then
    /// tells the server; a failure brings it back.
    func completeRemoval(_ pending: PendingRemoval) {
        pendingRemoval = nil
        let (shelfID, id) = (pending.focus.shelf, pending.focus.card)
        guard let row = shelves.firstIndex(where: { $0.id == shelfID }),
              let index = shelves[row].focusOrder.firstIndex(of: id) else { return }
        let rest = shelves[row].removing(card: id).focusOrder
        let neighbour = shelves.indices.contains(row + 1) ? row + 1 : row - 1
        let next = rest.isEmpty ? (shelves.indices.contains(neighbour) ? entry(shelves[neighbour]) : nil)
                                : HomeFocus(shelf: shelfID, card: rest[min(index, rest.count - 1)])
        if let next {
            heroFocus = next
            rowFocus[next.shelf] = next.card
            focused = next
        }
        store.remove(card: id, from: shelfID)
        Task {
            if let target = pending.watchlistTarget {
                // The store puts the title back if the server refuses.
                try? await watchlist.remove(target)
            } else {
                do { try await APIClient.shared.hideFromContinueWatching(seriesID: id) } catch { await store.reloadPlaybackRows() }
            }
        }
    }
}

/// A card leaving its Home row from its own context menu: hidden from Continue Watching,
/// or removed from the watchlist on the Watchlist row.
struct PendingRemoval: Equatable {
    let focus: HomeFocus
    /// Nil for a Continue Watching hide.
    let watchlistTarget: DetailsTarget?
}
