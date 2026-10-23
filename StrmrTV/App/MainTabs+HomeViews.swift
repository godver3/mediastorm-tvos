import SwiftUI

/// Home views in the top menu. The Home tab shows the chosen view and is labelled after it
/// ("Movies"); the View Switcher pill on Home (Settings › Home Layout, off by default)
/// opens the native menu of views. Views turned on in Settings › Top Menu get tabs of
/// their own and leave the menu; Home can still show any view without a tab. The pill hides once
/// every view has a tab, and Home goes back to All when its view gets one.
///
/// The state these use is internal on `MainTabs` rather than private.
extension MainTabs {
    /// Movies, Shows and pages shown as tabs of their own.
    var viewTabs: [String] {
        homeViews.ids.filter { $0 != HomeViews.all && menu.isVisible(homeView: $0) }
    }

    /// All plus the views without a tab of their own: what the Home tab can show.
    var pickableViews: [String] {
        let tabs = Set(viewTabs)
        return homeViews.ids.filter { !tabs.contains($0) }
    }

    /// The view the Home tab shows: the chosen one, or All once it has its own tab.
    var homeTabView: String {
        viewTabs.contains(homeViews.selected) ? HomeViews.all : homeViews.selected
    }

    var homeTabTitle: String {
        homeTabView == HomeViews.all ? String(localized: "Home") : homeViews.label(homeTabView)
    }

    /// The View Switcher menu's choices; nil (no pill) once every view has a tab of its own.
    var homeViewChoices: [String]? {
        pickableViews.count > 1 ? pickableViews : nil
    }

    func viewPath(_ view: String) -> Binding<NavigationPath> {
        Binding(get: { viewPaths[view] ?? NavigationPath() }, set: { viewPaths[view] = $0 })
    }
}

/// Keeps Home's view clear of the view tabs.
struct HomeViewTabs: ViewModifier {
    let tabs: MainTabs

    func body(content: Content) -> some View {
        content
            .onChange(of: tabs.viewTabs, initial: true) { _, views in
                // Home's view got a tab of its own: Home goes back to All.
                if views.contains(tabs.homeViews.selected) { tabs.homeViews.select(HomeViews.all) }
                // A view's tab went (turned off, or the page deleted): back to Home.
                if case let .homeView(view) = tabs.tab, !views.contains(view) { tabs.tab = .home }
            }
            .task { await tabs.homeViews.refresh() }
    }
}
