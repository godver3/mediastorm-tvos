#if os(iOS)
import SwiftUI

/// The signed-in phone app: a system tab bar in the Expo mobile app's order. Which sections
/// show follows the profile's menu (`MenuTabsStore`), as on the TV. On iPhone the bar's
/// five items are the first sections, Search and a More tab of our own (`MobileTabSplit`)
/// listing the rest (`MobileMoreList`). The system More wraps each tab's NavigationStack in
/// its own navigation bar, which stacked two bars on every page under it.
/// On iPad every section is a tab (or a sidebar row).
struct MobileMainView: View {
    /// Held, not observed: the stores' changes reach the screens through the environment.
    /// Observing them here re-ran this body, so rebuilt the tab view, on every store update,
    /// mid tab switch included, which knocked the tab bar's selection animation about.
    @StateObject private var stores = MobileMainStores()
    @ObservedObject private var menu = MenuTabsStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var homePath = NavigationPath()
    @State private var morePath = NavigationPath()

    init() {
        HomeViewsStore.shared.configure(profileID: APIClient.shared.profileID)
    }

    private var sections: [MobileSection] {
        let kids = AppSession.shared.profile?.isKidsProfile == true
        return MobileSection.allCases.filter { section in
            guard let tab = section.menuTab else { return true }
            // Kids profiles don't get Live TV (as in the Expo app).
            if section == .live, kids { return false }
            return menu.isVisible(tab)
        }
    }

    private var split: MobileTabSplit {
        MobileTabSplit(sections: sections, compact: sizeClass == .compact)
    }

    var body: some View {
        let split = split
        TabView {
            ForEach(split.tabs) { section in
                Tab(section.title, systemImage: section.symbol, role: section == .search ? .search : nil) {
                    stack(for: section)
                }
            }
            if !split.more.isEmpty {
                Tab("More", systemImage: "ellipsis") {
                    NavigationStack(path: $morePath) {
                        MobileMoreList(sections: split.more)
                            .navigationDestination(for: MobileSection.self) { $0.screen }
                            .mobileDestinations()
                    }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .mobileConnectionAccessory()
        .environmentObject(stores.watchlist)
        .environmentObject(stores.customLists)
        .environmentObject(stores.titles)
        .environmentObject(stores.listShelves)
        .task { await stores.watchlist.refresh() }
        .task { await stores.customLists.refresh() }
        .task { await stores.titles.refresh() }
        .task { await stores.listShelves.refresh() }
        .task { await BadgeSettingsStore.shared.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .continueWatchingChanged)) { _ in
            Task { await stores.titles.refreshContinueWatching() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .titleStateChanged)) { _ in
            stores.customLists.titlesChanged()
            Task { await stores.watchlist.refresh() }
        }
        .mobileLongPressModals(customLists: stores.customLists, titles: stores.titles)
    }

    @ViewBuilder
    private func stack(for section: MobileSection) -> some View {
        if section == .home {
            NavigationStack(path: $homePath) { section.screen.mobileDestinations() }
        } else {
            NavigationStack { section.screen.mobileDestinations() }
        }
    }
}

/// A top-level phone section, in the Expo mobile tab order.
enum MobileSection: String, CaseIterable, Identifiable, Hashable {
    case home, watchlist, search, lists, calendar, recordings, live, sports, profiles, downloads, settings

    var id: String { rawValue }

    /// The profile menu entry that shows or hides it; nil for sections always shown.
    var menuTab: MenuTab? {
        switch self {
        case .watchlist: .watchlist
        case .search: .search
        case .lists: .lists
        case .calendar: .calendar
        case .recordings: .recordings
        case .live: .live
        case .sports: .sports
        case .home, .profiles, .downloads, .settings: nil
        }
    }

    var title: String {
        switch self {
        case .home: String(localized: "Home")
        case .watchlist: String(localized: "Watchlist")
        case .search: String(localized: "Search")
        case .lists: String(localized: "Lists")
        case .calendar: String(localized: "Calendar")
        case .recordings: String(localized: "Recordings")
        case .live: String(localized: "Live")
        case .sports: String(localized: "Sports")
        case .profiles: String(localized: "Profiles")
        case .downloads: String(localized: "Downloads")
        case .settings: String(localized: "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .watchlist: "bookmark"
        case .search: "magnifyingglass"
        case .lists: "list.bullet.rectangle"
        case .calendar: "calendar"
        case .recordings: "record.circle"
        case .live: "dot.radiowaves.left.and.right"
        case .sports: "trophy"
        case .profiles: "person.2"
        case .downloads: "arrow.down.circle"
        case .settings: "gear"
        }
    }

    /// The section's root screen, without a NavigationStack (the caller provides one).
    @MainActor @ViewBuilder
    var screen: some View {
        switch self {
        case .home: MobileHomeView()
        case .watchlist: MobileWatchlistView()
        case .search: MobileSearchView()
        case .lists: MobileListsView()
        case .calendar: MobileCalendarView()
        case .recordings: MobileRecordingsView()
        case .live: MobileLiveView()
        case .sports: MobileSportsView()
        case .profiles: MobileProfilesView()
        case .downloads: MobileDownloadsView()
        case .settings: MobileSettingsView()
        }
    }
}
#endif
