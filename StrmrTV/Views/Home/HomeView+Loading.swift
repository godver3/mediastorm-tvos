import SwiftUI

/// Rows still loading hold focus: Down into Home lands on the first row on the page even
/// while it loads (its placeholder card), not on whichever row arrived first. Continue
/// Watching waits on the server while rows built on the device show at once, so on a cold
/// launch Down went past it, and it then appeared above the focused row.
extension HomeView {
    /// The first row's entry: its remembered or first card, or the placeholder of a row still
    /// loading. Failed rows are passed over, as is the row the carousel shows.
    var firstRowEntry: HomeFocus? {
        let source = carouselSource.id
        for slot in store.slots where slot.id != source {
            switch slot {
            case let .shelf(shelf):
                if let entry = entry(shelf) { return entry }
            case let .loading(id, _):
                return PlaceholderRow.focus(id)
            case .failed:
                continue
            }
        }
        return nil
    }

    /// Focus on a placeholder moves to the row's own entry once it loads. A row that fails or
    /// comes back empty hands focus to the next row down that can take it (a loaded row, or one
    /// still loading), else the nearest above.
    func refocusFromPlaceholder(_ slots: [HomeSlot]) {
        guard let current = focused ?? heroFocus, current.card == PlaceholderRow.focusCard, !slots.isEmpty else { return }
        // A row the profile no longer shows: from the top.
        let index = slots.firstIndex(where: { $0.id == current.shelf }) ?? 0
        if slots[index].id == current.shelf, slots[index].isLoading { return }
        let source = carouselSource.id
        let candidates = slots[index...] + slots[..<index].reversed()
        let next = candidates.lazy.filter { $0.id != source }.compactMap { slot -> HomeFocus? in
            switch slot {
            case let .shelf(shelf): entry(shelf)
            case let .loading(id, _): PlaceholderRow.focus(id)
            case .failed: nil
            }
        }.first
        guard let next else { return }
        heroFocus = next
        lastRowFocus = next
        // Covered by a details page, the refocus on the way back takes it.
        if !isCovered { focused = next }
    }
}
