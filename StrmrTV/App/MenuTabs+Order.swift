import SwiftUI

extension MenuTab {
    var title: String {
        switch self {
        case .live: String(localized: "Live")
        case .recordings: String(localized: "Recordings")
        case .sports: String(localized: "Sports")
        case .watchlist: String(localized: "Watchlist")
        case .lists: String(localized: "Lists")
        case .calendar: String(localized: "Calendar")
        case .search: String(localized: "Search")
        }
    }

    var symbol: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .recordings: "record.circle"
        case .sports: "trophy"
        case .watchlist: "bookmark"
        case .lists: "list.bullet.rectangle"
        case .calendar: "calendar"
        case .search: "magnifyingglass"
        }
    }
}

extension MenuTabsStore {
    /// The TV menu's tabs between Home and Settings that show on this device, by id, in the
    /// default order: Movies, Shows and pages with tabs of their own, then the sections.
    /// Kids profiles don't get Live (as in the Expo app).
    func shownTabIDs(homeViews: HomeViewsStore) -> [String] {
        let kids = AppSession.shared.profile?.isKidsProfile == true
        let views = homeViews.ids.filter { $0 != HomeViews.all && isVisible(homeView: $0) }
        let sections = MenuTab.allCases.filter { isVisible($0) && !(kids && $0 == .live) }
        return views + sections.map(\.rawValue)
    }

    /// `shownTabIDs` in this device's order.
    func orderedTabIDs(homeViews: HomeViewsStore) -> [String] {
        DeviceOrder.apply(order, to: shownTabIDs(homeViews: homeViews))
    }
}

extension MainTabs {
    /// The tabs between Home and Settings, in this device's order.
    var orderedTabs: [MainTab] {
        menu.orderedTabIDs(homeViews: homeViews).map { id in
            switch MenuTab(rawValue: id) {
            case .live: .live
            case .recordings: .recordings
            case .sports: .sports
            case .watchlist: .watchlist
            case .lists: .lists
            case .calendar: .calendar
            case .search: .search
            case nil: .homeView(id)
            }
        }
    }

    func tabTitle(_ tab: MainTab) -> String {
        switch tab {
        case let .homeView(view): homeViews.label(view)
        case .home: homeTabTitle
        case .settings: String(localized: "Settings")
        default: MenuTab(tab).map(\.title) ?? ""
        }
    }

    func tabSymbol(_ tab: MainTab) -> String {
        switch tab {
        case let .homeView(view): homeViews.icon(view)
        case .home: "house"
        case .settings: "gear"
        default: MenuTab(tab).map(\.symbol) ?? ""
        }
    }
}

private extension MenuTab {
    init?(_ tab: MainTabs.MainTab) {
        switch tab {
        case .live: self = .live
        case .recordings: self = .recordings
        case .sports: self = .sports
        case .watchlist: self = .watchlist
        case .lists: self = .lists
        case .calendar: self = .calendar
        case .search: self = .search
        case .home, .homeView, .settings: return nil
        }
    }
}
