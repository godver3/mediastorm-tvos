#if os(iOS)
import SwiftUI

/// The signed-in app's shared stores, created once. Never publishes itself, so the tab
/// view holding it doesn't re-render when one of them changes.
@MainActor
final class MobileMainStores: ObservableObject {
    let watchlist = WatchlistStore()
    let customLists = CustomListsStore()
    let titles = TitleStateStore()
    let listShelves = ListShelvesStore()
}

/// Which sections are tabs and which sit behind More. A compact-width tab bar holds five
/// items whatever the phone's width: past that UIKit moves the rest into its own More,
/// which stacks a second navigation bar on each page under it. So with more than five
/// sections the bar keeps Search (the bar's search tab) and More, and fills the other
/// slots with the first sections in order.
struct MobileTabSplit: Equatable {
    /// Items a compact tab bar shows before UIKit adds its own More.
    static let compactSlots = 5

    let tabs: [MobileSection]
    let more: [MobileSection]

    init(sections: [MobileSection], compact: Bool) {
        guard compact, sections.count > Self.compactSlots else {
            tabs = sections
            more = []
            return
        }
        let regular = sections.filter { $0 != .search }
        let shown = Set(regular.prefix(Self.compactSlots - 1 - (sections.contains(.search) ? 1 : 0)))
        tabs = sections.filter { $0 == .search || shown.contains($0) }
        more = regular.filter { !shown.contains($0) }
    }
}

/// The More tab's list of the sections past the tab bar, like the system More list.
struct MobileMoreList: View {
    let sections: [MobileSection]

    var body: some View {
        List(sections) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.symbol)
            }
        }
        .navigationTitle("More")
    }
}
#endif
