import Foundation

/// The profile's custom lists, shared by the Lists tab, the list grids and every
/// "Add to List…" action so a change in one shows everywhere.
@MainActor
final class CustomListsStore: ObservableObject {
    /// In the server's order; nil until the first load.
    @Published private(set) var lists: [CustomList]?
    /// The title whose "Add to List" sheet is up (set from any card or details page).
    @Published var picking: DetailsTarget?
    /// Bumped when a title is hidden, set aside or marked watched, which can change any
    /// grid: open list grids reload.
    @Published private(set) var revision = 0
    /// Per list ID, bumped when titles are added to or removed from that list, so only its
    /// own open grid updates (in place, keeping focus); other grids are left alone.
    @Published private(set) var itemRevisions: [String: Int] = [:]

    private var refreshTask: Task<Void, Never>?

    /// The lists a title can be added to: everything but the reserved Set Aside list,
    /// which only the Continue Watching actions manage.
    var userLists: [CustomList] { (lists ?? []).filter { !$0.isSetAside } }

    /// Loads the lists; concurrent callers share one request, and a failure keeps what was shown.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        let task = Task {
            if let loaded = try? await APIClient.shared.customLists() { lists = loaded }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// The stored item matching the title in each list that has it, by list ID. Lists
    /// that couldn't be read are left out.
    func memberships(of target: DetailsTarget) async -> [String: WatchlistItem] {
        await withTaskGroup(of: (String, WatchlistItem?)?.self) { group in
            for list in userLists where (list.itemCount ?? 1) > 0 {
                group.addTask {
                    guard let items = try? await APIClient.shared.customListItems(id: list.id) else { return nil }
                    return (list.id, items.first { WatchlistStore.matches($0, target) })
                }
            }
            var found: [String: WatchlistItem] = [:]
            for await result in group {
                if let (id, item) = result, let item { found[id] = item }
            }
            return found
        }
    }

    @discardableResult
    func create(name: String) async throws -> CustomList {
        let list = try await APIClient.shared.createCustomList(name: name)
        await refresh()
        return list
    }

    func rename(_ id: String, to name: String) async throws {
        try await APIClient.shared.renameCustomList(id: id, name: name)
        await refresh()
    }

    func delete(_ id: String) async throws {
        try await APIClient.shared.deleteCustomList(id: id)
        lists?.removeAll { $0.id == id }
        await refresh()
    }

    func add(_ target: DetailsTarget, to listID: String) async throws {
        try await APIClient.shared.addToCustomList(id: listID, target.watchlistUpsert)
        itemRevisions[listID, default: 0] += 1
        await refresh()
    }

    /// Removes a stored item (its own media type and ID, as the list returned it).
    func remove(_ item: WatchlistItem, from listID: String) async throws {
        try await APIClient.shared.removeFromCustomList(id: listID, mediaType: item.mediaType, itemID: item.id)
        itemRevisions[listID, default: 0] += 1
        await refresh()
    }

    /// A title was hidden, set aside or marked watched: open grids reload.
    func titlesChanged() {
        revision += 1
        Task { await refresh() }
    }

    /// Names other clients treat specially, or that are already taken.
    func nameProblem(_ name: String, renaming id: String? = nil) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String(localized: "Enter a name for the list.") }
        if trimmed.caseInsensitiveCompare("Set Aside") == .orderedSame {
            return String(localized: "“Set Aside” is reserved for titles parked out of Continue Watching.")
        }
        if (lists ?? []).contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return String(localized: "You already have a list called “\(trimmed)”.")
        }
        return nil
    }
}

extension DetailsTarget: Identifiable {
    var id: String { titleID }
}
