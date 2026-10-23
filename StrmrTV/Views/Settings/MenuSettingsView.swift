import SwiftUI

/// Settings › Menu: the menu's style (top bar or side menu) and which tabs it shows on
/// this device. Each starts on the
/// server's value ("Default") and is saved on this device only.
struct MenuSettingsView: View {
    @ObservedObject private var menu = MenuTabsStore.shared
    @ObservedObject private var homeViews = HomeViewsStore.shared
    @ObservedObject private var menuStyle = MenuStyleStore.shared

    var body: some View {
        Form {
            SettingsPageTitle("Menu")
            Section {
                OverridePicker("Menu Style", selection: $menuStyle.choice, options: MenuStyle.allCases,
                               profileValue: .top) { $0.label }
            } footer: {
                Text("Side Menu puts the menu on the left. Press Left at the screen's left edge, or Menu on a tab's first screen, to open it.")
            }
            Section {
                ForEach(MenuTab.allCases) { tab in
                    OverridePicker(tab.label, selection: menu.binding(for: tab), options: [true, false],
                                   profileValue: menu.profileShows(tab)) { $0 ? "Shown" : "Hidden" }
                }
                if !menu.overrides.isEmpty {
                    Button("Reset All to Default") { menu.resetOverrides() }
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Home and Settings are always shown. Live is never shown on kids profiles.")
            }
            Section {
                ForEach(homeViews.ids.filter { $0 != HomeViews.all }, id: \.self) { view in
                    OverridePicker("\(homeViews.label(view))", selection: menu.binding(forHomeView: view),
                                   options: [true, false], profileValue: menu.profileShows(homeView: view)) {
                        $0 ? "Shown" : "Hidden"
                    }
                }
            } header: {
                Text("Home Views")
            } footer: {
                Text("A Home view shown here gets its own tab, and Home shows everything. Otherwise press Select on Home to pick a view.")
            }
        }
        .settingsSubpage()
        .settingsListMargins(80)
        .task { await homeViews.refresh() }
    }
}
