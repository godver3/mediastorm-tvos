#if os(iOS)
import SwiftUI

/// The signed-in phone app: a system tab bar in the Expo mobile app's order. On iPhone the
/// tabs past the fourth go under More; on iPad the tab bar can become a sidebar. Which tabs
/// show follows the profile's menu (`MenuTabsStore`), as on the TV.
struct MobileMainView: View {
    @StateObject private var watchlist = WatchlistStore()
    @StateObject private var customLists = CustomListsStore()
    @StateObject private var titles = TitleStateStore()
    @StateObject private var listShelves = ListShelvesStore()
    @ObservedObject private var menu = MenuTabsStore.shared
    @State private var homePath = NavigationPath()

    init() {
        HomeViewsStore.shared.configure(profileID: APIClient.shared.profileID)
    }

    private var isKids: Bool { AppSession.shared.profile?.isKidsProfile == true }

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack(path: $homePath) {
                    MobileHomeView(store: HomeViewsStore.shared.store(for: HomeViews.all))
                        .mobileDestinations()
                }
            }
            if menu.isVisible(.watchlist) {
                Tab("Watchlist", systemImage: "bookmark") {
                    NavigationStack { MobileWatchlistView().mobileDestinations() }
                }
            }
            if menu.isVisible(.search) {
                Tab("Search", systemImage: "magnifyingglass", role: .search) {
                    NavigationStack { MobileSearchView().mobileDestinations() }
                }
            }
            if menu.isVisible(.lists) {
                Tab("Lists", systemImage: "list.bullet.rectangle") {
                    NavigationStack { MobileListsView().mobileDestinations() }
                }
            }
            if menu.isVisible(.calendar) {
                Tab("Calendar", systemImage: "calendar") {
                    NavigationStack { MobileCalendarView().mobileDestinations() }
                }
            }
            if menu.isVisible(.recordings) {
                Tab("Recordings", systemImage: "record.circle") {
                    NavigationStack { MobileRecordingsView().mobileDestinations() }
                }
            }
            // Kids profiles don't get Live TV (as in the Expo app).
            if menu.isVisible(.live), !isKids {
                Tab("Live", systemImage: "dot.radiowaves.left.and.right") {
                    NavigationStack { MobileLiveView().mobileDestinations() }
                }
            }
            if menu.isVisible(.sports) {
                Tab("Sports", systemImage: "trophy") {
                    NavigationStack { MobileSportsView().mobileDestinations() }
                }
            }
            Tab("Downloads", systemImage: "arrow.down.circle") {
                NavigationStack { MobileDownloadsView().mobileDestinations() }
            }
            Tab("Settings", systemImage: "gear") {
                NavigationStack { MobileSettingsView().mobileDestinations() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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
    }
}
#endif
