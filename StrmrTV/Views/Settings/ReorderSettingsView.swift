import SwiftUI

/// One item of a reorder list: its id and the name it's listed by.
struct ReorderItem: Identifiable, Equatable {
    let id: String
    let name: String
}

/// A TV settings page that reorders a list with the remote: Select picks an item up, Up and
/// Down carry it through the list, and Select (or Menu) puts it down. Each step is saved as
/// it happens, on this device only.
struct ReorderSettingsView: View {
    let title: LocalizedStringKey
    let items: [ReorderItem]
    let footer: LocalizedStringKey
    let isCustom: Bool
    /// Moves the first id to the second's place, among `items`' ids.
    let move: (String, String) -> Void
    let reset: () -> Void

    @State private var moving: String?
    @FocusState private var focused: String?

    var body: some View {
        Form {
            SettingsPageTitle(title)
            Section {
                ForEach(items) { item in
                    Button { select(item.id) } label: { row(item) }
                        .focused($focused, equals: item.id)
                        .accessibilityIdentifier("reorder.\(item.id)")
                }
            } footer: {
                Text(footer)
            }
            if isCustom {
                Section {
                    Button("Reset to Default") {
                        moving = nil
                        reset()
                    }
                }
            }
        }
        .settingsSubpage()
        .settingsListMargins(80)
        // Carrying an item: focus moving onto a neighbour moves the item there instead,
        // and focus stays on it.
        .onChange(of: focused) { _, next in
            guard let carried = moving else { return }
            guard let next else { moving = nil; return }
            guard next != carried else { return }
            move(carried, next)
            focused = carried
        }
        .onExitCommand(perform: moving == nil ? nil : { moving = nil })
    }

    private func select(_ id: String) {
        moving = moving == nil ? id : nil
    }

    private func row(_ item: ReorderItem) -> some View {
        HStack {
            if moving == item.id {
                Image(systemName: "arrow.up.and.down")
            }
            Text(item.name)
            Spacer()
            if moving == item.id {
                Text("Moving").foregroundStyle(.secondary)
            } else if moving == nil, focused == item.id {
                Text("Select to Move").foregroundStyle(.secondary)
            }
        }
    }
}
