#if os(iOS)
import SwiftUI

/// Settings › Home Layout on the phone: the TV's Top Carousel and Carousel Row
/// (`HomeStyleStore`), then each Home row's card style (Poster or Landscape) or Hidden,
/// saved on this device in `HomeLayoutStore`, as the TV's Home Layout › Rows. The TV's
/// focused-title, focus and card-size choices have no phone Home to apply to.
struct MobileHomeRowsSettingsView: View {
    @ObservedObject private var layout = HomeLayoutStore.shared
    @ObservedObject private var style = HomeStyleStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Top Carousel", isOn: $style.topCarousel)
                if style.topCarousel, !layout.shelves.isEmpty {
                    MobileOverridePicker("Carousel Row", selection: $style.carouselRow,
                                         defaultValue: HomeStyleStore.defaultRow(in: layout.shelves.map(\.id)),
                                         choices: layout.shelves.map { .init(value: $0.id, name: $0.title) })
                }
            } header: {
                Text("Top of Home")
            } footer: {
                Text("A carousel of one row's titles at the top of Home; that row isn't repeated below.")
            }
            Section {
                if layout.shelves.isEmpty {
                    Text("Open Home to list its rows.").foregroundStyle(.secondary)
                }
                ForEach(layout.shelves) { shelf in
                    MobileShelfStylePicker(shelf: shelf)
                }
            } header: {
                Text("Rows")
            } footer: {
                Text("Hidden rows are left off Home on this device. Continue Watching, My Upcoming, Watch Something, Dashboard, Streaming Services, Recently Watched and collection rows default to landscape cards; other rows to posters.")
            }
            if !layout.shelfStyles.isEmpty || !layout.hiddenShelves.isEmpty {
                Section {
                    Button("Reset All Rows to Default") { layout.resetShelfStyles() }
                }
            }
        }
        .navigationTitle("Home Layout")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One Home row's setting: Default (the style the row gets unless set), a style, or Hidden.
/// The phone draws the TV's expanding posters as posters, so they read as Poster here.
private struct MobileShelfStylePicker: View {
    @ObservedObject private var layout = HomeLayoutStore.shared
    let shelf: ShelfLayoutInfo

    private enum Setting: Hashable {
        case poster, landscape, hidden

        init(_ style: ShelfStyle) { self = style == .landscape ? .landscape : .poster }
    }

    var body: some View {
        MobileOverridePicker(title: Text(shelf.title), selection: selection,
                             defaultValue: Setting(layout.defaultStyle(for: shelf.id)), choices: [
                                 .init(value: .poster, name: String(localized: "Poster")),
                                 .init(value: .landscape, name: String(localized: "Landscape")),
                                 .init(value: .hidden, name: String(localized: "Hidden")),
                             ])
    }

    private var selection: Binding<Setting?> {
        Binding {
            layout.isHidden(shelf.id) ? .hidden : layout.shelfStyles[shelf.id].map(Setting.init)
        } set: { setting in
            layout.setHidden(setting == .hidden, for: shelf.id)
            switch setting {
            case .poster: layout.setStyle(.poster, for: shelf.id)
            case .landscape: layout.setStyle(.landscape, for: shelf.id)
            case .hidden: break
            case nil: layout.setStyle(nil, for: shelf.id)
            }
        }
    }
}

/// Settings › Tabs on the phone: which sections the tab bar (and More) shows on this device,
/// each starting on the profile's menu ("Default"), as the TV's Settings › Menu › Tabs.
struct MobileMenuSettingsView: View {
    @ObservedObject private var menu = MenuTabsStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(MenuTab.allCases) { tab in
                    MobileOverridePicker(title: Text(tab.label), selection: menu.binding(for: tab),
                                         defaultValue: menu.profileShows(tab), choices: [
                                             .init(value: true, name: String(localized: "Shown")),
                                             .init(value: false, name: String(localized: "Hidden")),
                                         ])
                }
            } footer: {
                Text("Home, Profiles, Downloads and Settings are always shown. Live is never shown on kids profiles. On iPhone the first four sections are tabs and the rest are under More.")
            }
            if !menu.overrides.isEmpty {
                Section {
                    Button("Reset All to Default") { menu.resetOverrides() }
                }
            }
        }
        .navigationTitle("Tabs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Card Badges and Spoilers on the phone: the TV's rows over `BadgeSettingsStore`
/// and `SpoilerSettingsStore`, each with "Default (…)", the profile's value.
struct MobileCardSettingsView: View {
    @ObservedObject private var badges = BadgeSettingsStore.shared
    @ObservedObject private var spoilers = SpoilerSettingsStore.shared

    var body: some View {
        Form {
            Section {
                MobileOverridePicker("Watch State", selection: $badges.watchState,
                                     defaultValue: badges.serverShows(.watchState), choices: MobileChoices.onOff)
                MobileOverridePicker("Release Status", selection: $badges.releaseStatus,
                                     defaultValue: badges.serverShows(.releaseStatus), choices: MobileChoices.onOff)
                MobileOverridePicker("Unwatched Count", selection: $badges.unwatchedCount,
                                     defaultValue: badges.serverShows(.unwatchedCount), choices: MobileChoices.onOff)
            } header: {
                Text("Card Badges")
            } footer: {
                Text("Watch State marks watched and in-progress titles; Release Status marks titles coming soon, unreleased or in theaters; Unwatched Count shows a series' episodes left to watch. Progress bars always show.")
            }

            Section {
                MobileOverridePicker("Hide Episode Thumbnails", selection: $spoilers.blurThumbnails,
                                     defaultValue: spoilers.server.blurThumbnails ?? false, choices: MobileChoices.onOff)
                if spoilers.blurThumbnails ?? spoilers.server.blurThumbnails ?? false {
                    MobileOverridePicker("Include Next Episode", selection: $spoilers.thumbnailsIncludeNext,
                                         defaultValue: spoilers.server.thumbnailsIncludeNext ?? false,
                                         choices: MobileChoices.onOff)
                }
                MobileOverridePicker("Hide Episode Descriptions", selection: $spoilers.blurOverviews,
                                     defaultValue: spoilers.server.blurOverviews ?? false, choices: MobileChoices.onOff)
                if spoilers.blurOverviews ?? spoilers.server.blurOverviews ?? false {
                    MobileOverridePicker("Include Next Episode", selection: $spoilers.overviewsIncludeNext,
                                         defaultValue: spoilers.server.overviewsIncludeNext ?? false,
                                         choices: MobileChoices.onOff)
                }
            } header: {
                Text("Spoilers")
            } footer: {
                Text("Blurs the artwork and hides the descriptions of episodes you haven't reached. Include Next Episode also hides the one you're up to.")
            }
        }
        .navigationTitle("Cards & Spoilers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await badges.refresh() }
        .task { await spoilers.refresh() }
    }
}
#endif
