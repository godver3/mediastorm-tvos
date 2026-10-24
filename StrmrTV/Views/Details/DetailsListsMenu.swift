import SwiftUI

/// The details page's Manage Lists as a menu, like the Live tab's category filter: each of the
/// profile's lists toggles the title in place with the menu left open (checked while the list
/// holds it); New List… creates one with the title in it. The memberships load with the page,
/// since a menu can't wait on a load when it opens. (A card's long press keeps the
/// `AddToListSheet`, which loads them itself.)
struct DetailsListsMenu: View {
    @EnvironmentObject private var store: CustomListsStore
    @EnvironmentObject private var titles: TitleStateStore
    let target: DetailsTarget

    /// The matching stored item per list ID; nil while loading.
    @State private var memberships: [String: WatchlistItem]?
    @State private var busy: Set<String> = []
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Menu {
            Section("Lists") {
                ForEach(store.userLists) { list in
                    let isMember = memberships?[list.id] != nil
                    Button { Task { await toggle(list) } } label: {
                        if isMember { Label(list.name, systemImage: "checkmark") } else { Text(list.name) }
                    }
                    .disabled(memberships == nil)
                    .menuActionDismissBehavior(.disabled)
                }
            }
            Button {
                newName = ""
                naming = true
            } label: {
                Label("New List…", systemImage: "plus")
            }
        } label: {
            Label("Manage Lists", systemImage: "text.badge.checkmark").labelStyle(.iconOnly)
        }
        .task(id: store.revision) {
            await store.refresh()
            memberships = await store.memberships(of: target)
        }
        .alert("New List", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create and Add") { Task { await createAndAdd() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The new list will start with \(target.name).")
        }
    }

    /// The check flips at once; repeat presses while a change is in flight are ignored.
    private func toggle(_ list: CustomList) async {
        guard !busy.contains(list.id), let memberships else { return }
        busy.insert(list.id)
        defer { busy.remove(list.id) }
        let item = memberships[list.id]
        do {
            if let item {
                self.memberships?[list.id] = nil
                try await store.remove(item, from: list.id)
            } else {
                try await store.add(target, to: list.id)
                // The server may store the title under another ID; read back what it kept.
                self.memberships = await store.memberships(of: target)
            }
        } catch {
            self.memberships?[list.id] = item
            titles.show(toast: String(localized: "Failed to update \(list.name)"))
        }
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = store.nameProblem(name) {
            titles.show(toast: problem)
            return
        }
        do {
            let list = try await store.create(name: name)
            try await store.add(target, to: list.id)
            titles.show(toast: String(localized: "Added to \(list.name)"))
        } catch {
            titles.show(toast: error.localizedDescription)
        }
    }
}
