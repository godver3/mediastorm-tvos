#if os(iOS)
import SwiftUI

/// A phone settings page that reorders a list by dragging its handles; each drop is saved,
/// on this device only, as the whole list.
struct MobileReorderView: View {
    let title: LocalizedStringKey
    let items: [ReorderItem]
    let footer: LocalizedStringKey
    let isCustom: Bool
    let save: ([String]) -> Void
    let reset: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    Text(item.name)
                        .accessibilityIdentifier("reorder.\(item.id)")
                }
                .onMove { from, to in
                    var ids = items.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    save(ids)
                }
            } footer: {
                Text(footer)
            }
            if isCustom {
                Section {
                    Button("Reset to Default", action: reset)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Home Layout › Row Order on the phone.
struct MobileRowOrderView: View {
    @ObservedObject private var layout = HomeLayoutStore.shared
    @ObservedObject private var order = ShelfOrderStore.shared

    var body: some View {
        MobileReorderView(title: "Row Order",
                          items: order.ordered(layout.shelves, id: \.id).map { ReorderItem(id: $0.id, name: $0.title) },
                          footer: "Drag rows into the order Home shows them. Saved on this device only; rows added to the profile later keep their place after the row before them.",
                          isCustom: order.isCustom, save: order.set, reset: order.reset)
    }
}

/// Settings › Tabs › Tab Order on the phone: the sections after Home. On iPhone the first
/// ones fill the tab bar and the rest go under More.
struct MobileTabOrderView: View {
    @ObservedObject private var menu = MenuTabsStore.shared

    var body: some View {
        MobileReorderView(title: "Tab Order",
                          items: MobileSection.shown(menu: menu).filter { $0 != .home }
                              .map { ReorderItem(id: $0.rawValue, name: $0.title) },
                          footer: "Drag sections into the order the tab bar shows them. On iPhone the first ones fill the tab bar and the rest are under More. Home stays first. Search keeps the bar's search button while it's the last tab. Saved on this device only.",
                          isCustom: !menu.order.isEmpty, save: menu.setTabOrder, reset: menu.resetTabOrder)
    }
}
#endif
