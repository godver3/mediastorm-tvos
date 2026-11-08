#if os(iOS)
import SwiftUI

/// A list page's titles, fetched a page at a time as the grid nears its end, sorted and
/// filtered by the server (`BrowseOptions`, plus the phone's title filter). Any change of
/// options reloads from the first page; the TV's `BrowseGridView` pages the same way.
@MainActor
final class MobileBrowseModel: ObservableObject {
    let list: BrowseList
    private static let pageSize = 60

    @Published var options = BrowseOptions() { didSet { if options != oldValue { reload() } } }
    /// Filters the profile's own lists by title (`titleFilter`), 250 ms after typing stops.
    @Published var titleFilter = "" { didSet { if titleFilter != oldValue { scheduleFilter() } } }
    @Published private(set) var entries: [BrowseEntry] = []
    @Published private(set) var total: Int?
    @Published private(set) var genres: [String] = []
    @Published private(set) var letters: [String] = []
    @Published private(set) var loadError: String?
    @Published private(set) var isLoadingPage = false

    /// Items read so far (duplicates dropped from `entries` included).
    private var fetched = 0
    private var generation = 0
    private var appliedFilter = ""
    private var filterTask: Task<Void, Never>?

    init(list: BrowseList) { self.list = list }

    var isFiltered: Bool { options.isFiltered || options.letter != nil || !appliedFilter.isEmpty }

    private var extra: [String: String] {
        var extra = list.quickPageQuery ?? [:]
        if list.filters, !appliedFilter.isEmpty { extra["titleFilter"] = appliedFilter }
        return extra
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let trimmed = titleFilter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed != appliedFilter else { return }
            appliedFilter = trimmed
            reload()
        }
    }

    /// From the first page.
    func reload() {
        generation += 1
        entries = []
        fetched = 0
        total = nil
        loadError = nil
        isLoadingPage = false
        Task { await loadPage() }
    }

    /// First load only: coming back to the page keeps what it showed.
    func loadIfNeeded() async {
        guard total == nil, !isLoadingPage, loadError == nil else { return }
        await loadPage()
    }

    func loadPage() async {
        guard !isLoadingPage, total.map({ fetched < $0 }) ?? true else { return }
        let request = generation, requested = options, offset = fetched
        isLoadingPage = true
        defer { if request == generation { isLoadingPage = false } }
        do {
            let page = try await APIClient.shared.browsePage(list, options: requested, limit: Self.pageSize, offset: offset,
                                                             extra: extra)
            guard request == generation else { return }
            if list.quickPageQuery != nil { Task { await fillArtwork(offset: offset, generation: request) } }
            apply(page, replacing: false)
        } catch {
            // A cancelled load (the page's `.task` ending on a tab switch) is retried when
            // the page shows again; only a real failure shows, and only over an empty grid.
            guard !error.isCancellation else { return }
            if request == generation, entries.isEmpty { loadError = error.localizedDescription }
        }
    }

    private func apply(_ page: BrowsePage, replacing: Bool) {
        if fetched == 0 || replacing {
            genres = page.genres
            letters = page.letters
        }
        fetched += page.entries.count
        var seen = Set(entries.map(\.id))
        entries += page.entries.filter { seen.insert($0.id).inserted }
        total = page.listSize(fetched: fetched)
        loadError = nil
    }

    /// Swaps a quick page's cards for the full page's (the same titles with text posters).
    private func fillArtwork(offset: Int, generation request: Int) async {
        var full = extra
        for key in (list.quickPageQuery ?? [:]).keys { full[key] = nil }
        guard let page = try? await APIClient.shared.browsePage(list, options: options, limit: Self.pageSize, offset: offset,
                                                                 extra: full),
              request == generation else { return }
        let byID = Dictionary(page.entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        entries = entries.map { byID[$0.id] ?? $0 }
    }

    /// Re-reads what is loaded without blanking the grid (pull to refresh, a title removed
    /// or hidden elsewhere).
    func refreshInPlace() async {
        guard total != nil, !isLoadingPage else { return reload() }
        let request = generation, wanted = max(fetched, 1)
        var read: [BrowseEntry] = []
        var first: BrowsePage?
        var size = 0
        repeat {
            guard let page = try? await APIClient.shared.browsePage(list, options: options, limit: Self.pageSize,
                                                                     offset: read.count, extra: extra),
                  request == generation else { return }
            if first == nil { first = page }
            read += page.entries
            size = page.listSize(fetched: read.count)
            if page.entries.isEmpty { break }
        } while read.count < wanted && read.count < size
        var seen = Set<String>()
        entries = read.filter { seen.insert($0.id).inserted }
        fetched = read.count
        total = size
        genres = first?.genres ?? []
        letters = first?.letters ?? []
    }

    /// Drops an entry at once (a title removed from this list); `restore` puts it back.
    func drop(_ id: String) -> () -> Void {
        let previous = (entries, fetched, total)
        entries.removeAll { $0.id == id }
        fetched = max(0, fetched - 1)
        total = total.map { max(0, $0 - 1) }
        return { [weak self] in
            guard let self else { return }
            (entries, fetched, total) = previous
        }
    }

    /// One entry at a random position of the whole (filtered) list, not only the loaded pages.
    func randomEntry() async -> BrowseEntry? {
        let count = total ?? fetched
        guard count > 0 else { return nil }
        for _ in 0..<6 {
            let offset = Int.random(in: 0..<count)
            let entry: BrowseEntry? = if offset < entries.count, fetched == entries.count {
                entries[offset]
            } else {
                try? await APIClient.shared.browsePage(list, options: options, limit: 1, offset: offset, extra: extra).entries.first
            }
            // An unmatched library file has no page to open: try another.
            if case let .library(library)? = entry, library.detailsTarget == nil, !library.group.isShow { continue }
            return entry
        }
        return nil
    }
}
#endif
