import SwiftUI

/// "Manage Lists…": each of the profile's lists with a check on those that already hold
/// the title. Selecting a list adds or removes the title in place; "New List…" creates
/// one with the title in it.
struct AddToListSheet: View {
    @EnvironmentObject private var store: CustomListsStore
    @Environment(\.dismiss) private var dismiss
    let target: DetailsTarget

    /// The matching stored item per list ID; nil while loading.
    @State private var memberships: [String: WatchlistItem]?
    @State private var busy: Set<String> = []
    @State private var error: String?
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Manage Lists").font(.title2.weight(.bold))
                Text(target.name).font(.headline).foregroundStyle(.secondary)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if memberships == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        ForEach(store.userLists) { list in row(list) }
                    }
                    Button {
                        newName = ""
                        naming = true
                    } label: {
                        Label("New List…", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(40)
            }
            .scrollClipDisabled()
        }
        .padding(80)
        .frame(width: 1100)
        .task {
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

    private func row(_ list: CustomList) -> some View {
        let isMember = memberships?[list.id] != nil
        return Button {
            Task { await toggle(list) }
        } label: {
            HStack {
                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                Text(list.name)
                Spacer()
                if busy.contains(list.id) {
                    ProgressView()
                } else if let count = list.itemCount {
                    Text("\(count)").foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityValue(isMember ? Text("In list") : Text("Not in list"))
    }

    /// Repeat presses on a list with a change in flight are ignored (disabling the focused
    /// row would drop focus off the sheet).
    private func toggle(_ list: CustomList) async {
        guard !busy.contains(list.id) else { return }
        busy.insert(list.id)
        defer { busy.remove(list.id) }
        do {
            if let item = memberships?[list.id] {
                try await store.remove(item, from: list.id)
                memberships?[list.id] = nil
            } else {
                try await store.add(target, to: list.id)
                // The server may store the title under another ID; read back what it kept.
                memberships = await store.memberships(of: target)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = store.nameProblem(name) {
            error = problem
            return
        }
        do {
            let list = try await store.create(name: name)
            try await store.add(target, to: list.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// "Manage Lists…" for a card's context menu: the sheet adds and removes.
struct AddToListMenuButton: View {
    @EnvironmentObject private var store: CustomListsStore
    let target: DetailsTarget

    var body: some View {
        Button { store.picking = target } label: {
            Label("Manage Lists…", systemImage: "text.badge.checkmark")
        }
    }
}
