#if os(iOS)
import SwiftUI

/// The signed-in phone app: a system tab bar in the Expo mobile app's order. Which sections
/// show follows the profile's menu (`MenuTabsStore`), as on the TV. On iPhone the first four
/// are tabs and the rest sit in a More tab of our own: the system More wraps each tab's
/// NavigationStack in its own navigation bar, which stacked two bars on every page under it.
/// On iPad every section is a tab (or a sidebar row).
struct MobileMainView: View {
    @StateObject private var watchlist = WatchlistStore()
    @StateObject private var customLists = CustomListsStore()
    @StateObject private var titles = TitleStateStore()
    @StateObject private var listShelves = ListShelvesStore()
    @ObservedObject private var menu = MenuTabsStore.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var homePath = NavigationPath()
    @State private var morePath = NavigationPath()

    /// Tabs on a compact-width screen before the rest go under More.
    private static let compactTabs = 4

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

    private var split: (tabs: [MobileSection], more: [MobileSection]) {
        let all = sections
        guard sizeClass == .compact, all.count > Self.compactTabs + 1 else { return (all, []) }
        return (Array(all.prefix(Self.compactTabs)), Array(all.dropFirst(Self.compactTabs)))
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
        .environmentObject(watchlist)
        .environmentObject(customLists)
        .environmentObject(titles)
        .environmentObject(listShelves)
        .task { await watchlist.refresh() }
        .task { await customLists.refresh() }
        .task { await titles.refresh() }
        .task { await listShelves.refresh() }
        .task { await BadgeSettingsStore.shared.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .continueWatchingChanged)) { _ in
            Task { await titles.refreshContinueWatching() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .titleStateChanged)) { _ in
            customLists.titlesChanged()
            Task { await watchlist.refresh() }
        }
        .mobileLongPressModals(customLists: customLists, titles: titles)
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

/// The More tab's list of the sections past the tab bar, like the system More list.
private struct MobileMoreList: View {
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
