import SwiftUI

/// A list from the Lists tab as a poster grid, fetched a page at a time as the grid
/// nears its end. The server sorts and filters (`BrowseOptions`); pages are shown in
/// its order, and any change reloads from the first page.
struct BrowseGridView: View {
    let list: BrowseList

    @EnvironmentObject private var store: CustomListsStore
    @Environment(\.dismiss) private var dismiss

    private static let pageSize = 60

    @State private var options = BrowseOptions()
    @State private var entries: [BrowseEntry] = []
    /// Items read from the server so far (duplicates dropped from `entries` included).
    @State private var fetched = 0
    @State private var total: Int?
    @State private var genres: [String] = []
    @State private var letters: [String] = []
    @State private var loadError: String?
    /// The options of the page being fetched; a fetch for older options doesn't block one
    /// for the current options.
    @State private var loadingFor: BrowseOptions?
    @State private var gridWidth: CGFloat = 0
    /// The random pick, pushed as its details page (an unmatched library show: its episodes).
    @State private var pick: DetailsTarget?
    @State private var pickedShow: LibraryShowTarget?
    @State private var isPicking = false
    /// `store.revision` the entries were loaded at; a hide, set-aside or watched change reloads.
    @State private var loadedRevision: Int?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var actionError: String?

    var body: some View {
        GridPage(title: title, gridWidth: $gridWidth) {
            if hasControls {
                BrowseControls(list: list, options: $options, genres: genres,
                               isPicking: isPicking, onRandom: list.offersRandom ? { Task { await pickRandom() } } : nil,
                               onRename: isManageable ? { newName = title; renaming = true } : nil,
                               onDelete: isManageable ? { confirmingDelete = true } : nil)
            }
            if let actionError {
                Text(actionError).font(.callout).foregroundStyle(.red)
            }
            if list.indexesLetters, options.sort == .name, !letters.isEmpty {
                LetterIndex(letters: letters, selection: $options.letter)
            }
            if !entries.isEmpty {
                // Half a page ahead, so a cold page (seconds) is usually in before the end.
                CardGrid(items: entries, cardWidth: PosterCard.width, available: gridWidth,
                         onNearEnd: { Task { await loadPage() } }, nearEndRows: 6) { entry, width in
                    switch entry {
                    case let .title(title): PosterCard(title: title, width: width)
                    case let .item(item):
                        PosterCard(item: item, width: width,
                                   onRemoveFromList: removeAction(item))
                    case let .library(entry): LibraryPosterCard(entry: entry, width: width)
                    }
                }
                // The next page is on its way: the grid hasn't ended.
                if loadingFor == options {
                    ProgressView().frame(maxWidth: .infinity).padding(.bottom, 40)
                }
            } else if let loadError {
                GridMessage(text: loadError)
            } else if total == 0 {
                let filtered = options.isFiltered || options.letter != nil
                // Unfiltered, the last title may just have been removed here: the message
                // keeps focus on the page (filtered, focus is still on the controls).
                GridMessage(text: filtered
                            ? String(localized: "No titles match these filters.")
                            : String(localized: "Nothing in this list yet."),
                            holdsFocus: !filtered)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
            }
        }
        // Runs on appear and again from the first page whenever the sort or a filter changes.
        .task(id: ReloadKey(options: options, revision: store.revision)) { await reload() }
        // Titles added to or removed from this list (from any Add to List sheet): update in place.
        .onChange(of: customID.flatMap { store.itemRevisions[$0] }) { Task { await refreshInPlace() } }
        .alert("Rename List", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { Task { await rename() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(title)”?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete List", role: .destructive) { Task { await deleteList() } }
        } message: {
            Text("The titles stay in your library; only the list goes.")
        }
        .navigationDestination(item: $pick) { DetailsView(target: $0) }
        .navigationDestination(item: $pickedShow) { LibraryShowView(target: $0) }
    }

    private var hasControls: Bool { !list.sorts.isEmpty || list.filters || list.offersRandom || list.parts.count > 1 }

    private struct ReloadKey: Equatable {
        let options: BrowseOptions
        let revision: Int
    }

    private var customID: String? {
        if case let .custom(id, _) = list { return id }
        return nil
    }

    /// A custom list shows its current name (it may have been renamed here or elsewhere).
    private var title: String {
        guard let customID, let current = store.lists?.first(where: { $0.id == customID }) else { return list.title }
        return current.name
    }

    /// "Remove from This List" in a custom list's grid; not in Set Aside, whose own
    /// Remove from Set Aside covers it.
    private func removeAction(_ item: WatchlistItem) -> (() -> Void)? {
        guard isManageable, let customID else { return nil }
        return { Task { await remove(item, from: customID) } }
    }

    /// Rename and delete: the profile's own lists, not the reserved Set Aside.
    private var isManageable: Bool {
        guard let customID else { return false }
        return !(store.lists?.first { $0.id == customID }?.isSetAside ?? true)
    }

    private func reload() async {
        // Returning from details re-runs the task with the same options: keep the grid.
        // A title hidden, set aside or marked watched meanwhile (from a card here or a
        // details page) re-reads it in place, so focus stays on the card, not the controls.
        if !entries.isEmpty, loadedOptions == options {
            guard loadedRevision != store.revision else { return }
            loadedRevision = store.revision
            await refreshInPlace()
            return
        }
        loadedRevision = store.revision
        entries = []
        fetched = 0
        total = nil
        loadError = nil
        await loadPage()
    }

    /// The options the loaded entries were fetched with.
    @State private var loadedOptions: BrowseOptions?

    private func loadPage() async {
        let requested = options
        guard loadingFor != requested, total.map({ fetched < $0 }) ?? true else { return }
        loadingFor = requested
        defer { if loadingFor == requested { loadingFor = nil } }
        do {
            let offset = fetched
            let quick = list.quickPageQuery
            let page = try await APIClient.shared.browsePage(list, options: requested, limit: Self.pageSize, offset: offset,
                                                             extra: quick ?? [:])
            // The sort or a filter changed while this page was loading; that reload wins.
            guard requested == options else { return }
            if quick != nil { Task { await fillArtwork(offset: offset, options: requested) } }
            if fetched == 0 {
                genres = page.genres
                letters = page.letters
            }
            fetched += page.entries.count
            var seen = Set(entries.map(\.id))
            entries += page.entries.filter { seen.insert($0.id).inserted }
            // A short page means the list ended, whatever the total said.
            total = page.entries.count < Self.pageSize ? fetched : page.total
            loadedOptions = requested
            loadError = nil
        } catch {
            if entries.isEmpty, requested == options { loadError = error.localizedDescription }
        }
    }

    /// Swaps a quick page's cards for the full page's (same titles, with their text
    /// posters) in place, so focus stays where it is.
    private func fillArtwork(offset: Int, options requested: BrowseOptions) async {
        guard let page = try? await APIClient.shared.browsePage(list, options: requested, limit: Self.pageSize, offset: offset),
              requested == options else { return }
        let full = Dictionary(page.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entries = entries.map { full[$0.id] ?? $0 }
    }

    /// Re-reads the loaded part without clearing it: cards that stay keep their focus, a
    /// removed card's focus moves to a neighbour, an emptied list shows its focusable message.
    private func refreshInPlace() async {
        guard loadedOptions == options, loadingFor == nil, total != nil else { return }
        let requested = options
        let limit = max(Self.pageSize, fetched + 1)
        guard let page = try? await APIClient.shared.browsePage(list, options: requested, limit: limit, offset: 0),
              requested == options else { return }
        var seen = Set<String>()
        entries = page.entries.filter { seen.insert($0.id).inserted }
        fetched = page.entries.count
        total = page.entries.count < limit ? fetched : page.total
        genres = page.genres
        letters = page.letters
    }

    /// Drops the title here at once so focus keeps its place, then tells the server.
    private func remove(_ item: WatchlistItem, from listID: String) async {
        let previous = (entries, fetched, total)
        entries.removeAll { $0.id == item.id }
        fetched = max(0, fetched - 1)
        total = total.map { max(0, $0 - 1) }
        do {
            try await store.remove(item, from: listID)
            actionError = nil
        } catch {
            (entries, fetched, total) = previous
            actionError = error.localizedDescription
        }
    }

    private func rename() async {
        guard let customID else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != title else { return }
        if let problem = store.nameProblem(name, renaming: customID) {
            actionError = problem
            return
        }
        do {
            try await store.rename(customID, to: name)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteList() async {
        guard let customID else { return }
        do {
            try await store.delete(customID)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// One title at a random position of the whole (filtered) list, not just the pages
    /// loaded so far.
    private func pickRandom() async {
        guard !isPicking else { return }
        isPicking = true
        defer { isPicking = false }
        let count = total ?? fetched
        guard count > 0 else { return }
        // A library's unmatched files have no page to open: try a few other picks.
        for _ in 0..<6 {
            let offset = Int.random(in: 0..<count)
            let entry: BrowseEntry? = if offset < entries.count, fetched == entries.count {
                entries[offset]
            } else {
                try? await APIClient.shared.browsePage(list, options: options, limit: 1, offset: offset).entries.first
            }
            switch entry {
            case nil: return
            case let .title(title)?: pick = DetailsTarget(title)
            case let .item(item)?: pick = DetailsTarget(item)
            case let .library(entry)?:
                if let target = entry.detailsTarget {
                    pick = target
                } else if entry.group.isShow {
                    pickedShow = LibraryShowTarget(entry: entry)
                } else {
                    continue
                }
            }
            return
        }
    }
}
