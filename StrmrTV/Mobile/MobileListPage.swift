#if os(iOS)
import SwiftUI

/// A whole list, opened from a Lists tile, a Home row's title or explore card, a streaming
/// service or Ask AI (Expo's `shelf` route): Continue Watching and Hidden have their own
/// grids; every other list pages from the server as a poster grid.
struct MobileListPage: View {
    let list: BrowseList

    var body: some View {
        switch list {
        case .continueWatching: MobileContinueWatchingGrid()
        case .hidden: MobileHiddenGrid()
        default: MobileBrowseGrid(list: list)
        }
    }
}

/// A list as a poster grid with its sort, filters, random pick and (the profile's own
/// lists) rename and delete in the toolbar, a title filter in the search field.
struct MobileBrowseGrid: View {
    @StateObject private var model: MobileBrowseModel
    @EnvironmentObject private var store: CustomListsStore
    @EnvironmentObject private var watchlist: WatchlistStore
    @Environment(\.dismiss) private var dismiss

    @State private var pick: DetailsTarget?
    @State private var pickedShow: LibraryShowTarget?
    @State private var isPicking = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    @State private var actionError: String?
    @State private var loadedRevision: Int?

    init(list: BrowseList) {
        _model = StateObject(wrappedValue: MobileBrowseModel(list: list))
    }

    private var list: BrowseList { model.list }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if list.parts.count > 1 {
                    Picker("List", selection: $model.options.part) {
                        ForEach(Array(list.parts.enumerated()), id: \.offset) { Text($1).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                }
                if list.indexesLetters, model.options.sort == .name, !model.letters.isEmpty {
                    MobileLetterStrip(letters: model.letters, selection: $model.options.letter)
                }
                if let actionError {
                    Text(actionError).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16)
                }
                if !model.entries.isEmpty {
                    MobilePosterGrid(items: model.entries, onNearEnd: { Task { await model.loadPage() } }) { entry in
                        MobileGridCard(card: HomeCard(entry), onRemoveFromList: removeAction(entry))
                    }
                    if model.isLoadingPage { ProgressView().frame(maxWidth: .infinity).padding() }
                } else {
                    MobileScrollStatus { status }
                }
            }
            .padding(.vertical, 8)
        }
        .refreshable { await model.refreshInPlace() }
        .navigationTitle(title)
        // A long name (an Ask AI prompt) would be cut off as a large title.
        .navigationBarTitleDisplayMode(title.count > 24 ? .inline : .large)
        .modifier(TitleFilter(enabled: list.filters, text: $model.titleFilter))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                MobileBrowseMenus(list: list, options: $model.options, genres: model.genres,
                                  onRandom: list.offersRandom ? { Task { await pickRandom() } } : nil,
                                  isPicking: isPicking,
                                  onRename: isManageable ? { newName = title; renaming = true } : nil,
                                  onDelete: isManageable ? { confirmingDelete = true } : nil)
            }
        }
        .task { await model.loadIfNeeded() }
        // Hidden, set aside or watched elsewhere; titles added to or removed from this list.
        .onChange(of: store.revision) { Task { await model.refreshInPlace() } }
        .onChange(of: customID.flatMap { store.itemRevisions[$0] }) { Task { await model.refreshInPlace() } }
        .onChange(of: watchlist.items.count) {
            if list == .watchlist { Task { await model.refreshInPlace() } }
        }
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
        .navigationDestination(item: $pick) { MobileDetailsView(target: $0) }
        .navigationDestination(item: $pickedShow) { MobileLibraryShowView(target: $0) }
    }

    /// What an empty grid shows: why it failed, that it is empty, or that it is loading.
    @ViewBuilder
    private var status: some View {
        if model.entries.isEmpty {
            if let error = model.loadError {
                ContentUnavailableView {
                    Label("Couldn't Load List", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { model.reload() }.buttonStyle(.bordered)
                }
            } else if model.total == 0 {
                if model.isFiltered {
                    ContentUnavailableView("No Matches", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("No titles match these filters."))
                } else {
                    ContentUnavailableView("Nothing Here Yet", systemImage: "list.bullet",
                                           description: Text("Nothing in this list yet."))
                }
            } else {
                ProgressView()
            }
        }
    }

    private var customID: String? {
        if case let .custom(id, _) = list { return id }
        return nil
    }

    /// A custom list shows its current name (it may have been renamed).
    private var title: String {
        guard let customID, let current = store.lists?.first(where: { $0.id == customID }) else { return list.title }
        return current.name
    }

    /// Rename and delete: the profile's own lists, not the reserved Set Aside.
    private var isManageable: Bool {
        guard let customID else { return false }
        return !(store.lists?.first { $0.id == customID }?.isSetAside ?? true)
    }

    private func removeAction(_ entry: BrowseEntry) -> (() -> Void)? {
        guard isManageable, let customID, case let .item(item) = entry else { return nil }
        return {
            Task {
                let restore = model.drop(item.id)
                do {
                    try await store.remove(item, from: customID)
                    actionError = nil
                } catch {
                    restore()
                    actionError = error.localizedDescription
                }
            }
        }
    }

    private func pickRandom() async {
        guard !isPicking else { return }
        isPicking = true
        defer { isPicking = false }
        switch await model.randomEntry() {
        case let .title(title)?: pick = DetailsTarget(title)
        case let .item(item)?: pick = DetailsTarget(item)
        case let .library(entry)?:
            if let target = entry.detailsTarget { pick = target } else { pickedShow = LibraryShowTarget(entry: entry) }
        case nil: break
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
}

/// The search field as a title filter, on the lists the server filters by title.
private struct TitleFilter: ViewModifier {
    let enabled: Bool
    @Binding var text: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter titles")
        } else {
            content
        }
    }
}

/// Jump-to-letter chips for a list sorted by name; choosing the chosen one again shows all.
struct MobileLetterStrip: View {
    let letters: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(letters, id: \.self) { letter in
                    let selected = selection == letter
                    Button {
                        selection = selected ? nil : letter
                    } label: {
                        Text(letter).font(.subheadline.weight(.semibold)).frame(minWidth: 22)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(selected ? .accentColor : .secondary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollIndicators(.hidden)
    }
}
#endif
