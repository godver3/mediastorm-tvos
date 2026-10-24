import Foundation
import SwiftUI

/// What the Live tab lists: every channel, the favorites, or one or more categories.
enum LiveFilter: Hashable {
    case all
    case favorites
    /// Never empty: no categories is `.all` (see `selecting`).
    case categories(Set<String>)

    /// `names` as a filter: `.all` when there are none.
    static func selecting(_ names: Set<String>) -> LiveFilter {
        names.isEmpty ? .all : .categories(names)
    }

    var categories: Set<String> {
        if case let .categories(names) = self { names } else { [] }
    }

    var label: String {
        switch self {
        case .all: String(localized: "All Channels")
        case .favorites: String(localized: "Favorites")
        case let .categories(names) where names.count == 1: names.first!
        case let .categories(names): String(localized: "\(names.count) Categories")
        }
    }
}

/// The Live tab's channels and guide data, for the active profile.
///
/// Channels come a page at a time from the server, which applies the source, category and
/// search filters; hidden channels are dropped here. Favorites are listed only under the
/// Favorites filter, not pinned to the top of the others. Favorites and
/// hidden channels live in the profile's settings (`liveTV`), shared with the Expo app; the
/// category selection is kept on this device, per profile, and restored on return.
/// Now / next and guide schedules are fetched in batches for the channels on screen.
@MainActor
final class LiveStore: ObservableObject {
    // Filters. Changing any of them reloads from the first page.
    @Published var filter: LiveFilter {
        didSet {
            guard filter != .favorites else { return }
            filterBeforeFavorites = filter
            defaults.set(filter.categories.sorted(), forKey: Self.categoriesKey(profileID))
        }
    }
    @Published var sourceID: String?
    /// Debounced into `search` before it reaches the server.
    @Published var searchText = ""
    @Published private(set) var search = ""
    @Published var showHidden = false

    @Published private(set) var channels: [LiveChannel] = []
    @Published private(set) var total: Int?
    @Published private(set) var categories: [String] = []
    @Published private(set) var sources: [LiveSource] = []
    @Published private(set) var loadError: String?
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var actionError: String?
    /// nil until known; the guide is only offered when the EPG is on.
    @Published private(set) var epgEnabled: Bool?

    /// Now / next by `LiveChannel.guideKey`.
    @Published private(set) var nowNext: [String: EPGNowPlaying] = [:]
    /// Guide programmes by `LiveChannel.guideKey`, sorted, de-duplicated by start.
    @Published private(set) var schedules: [String: [EPGProgram]] = [:]

    private static let pageSize = 250
    private(set) var hasMore = true
    private var loadingFor: Query?
    private var loadedFor: Query?
    private var searchDebounce: Task<Void, Never>?
    private var listsLoaded = false
    /// Where the header's star goes back to when Favorites is turned off.
    private var filterBeforeFavorites: LiveFilter = .all

    private var nowNextFetched: [String: Date] = [:]
    private var nowNextPending = Set<String>()
    private var nowNextTask: Task<Void, Never>?

    /// Guide data is fetched in fixed six-hour chunks from `guideBase`, per key.
    let guideBase = LiveStore.halfHour(Date()).addingTimeInterval(-1800)
    static let chunk: TimeInterval = 6 * 3600
    private var chunksLoaded = Set<String>()
    private var chunksPending: [Int: Set<String>] = [:]
    private var chunkTask: Task<Void, Never>?

    private let api = APIClient.shared
    private let defaults: UserDefaults
    private let profileID: String

    static func categoriesKey(_ profile: String) -> String { "live.categories.\(profile)" }

    init(defaults: UserDefaults = .standard, profileID: String = APIClient.shared.profileID) {
        self.defaults = defaults
        self.profileID = profileID
        let saved = LiveFilter.selecting(Set(defaults.stringArray(forKey: Self.categoriesKey(profileID)) ?? []))
        filter = saved
        filterBeforeFavorites = saved
    }

    struct Query: Equatable {
        let filter: LiveFilter
        let sourceID: String?
        let search: String
    }

    var query: Query { Query(filter: filter, sourceID: sourceID, search: search) }

    /// The channels to show: hidden ones only while `showHidden` is on.
    var visibleChannels: [LiveChannel] {
        showHidden || hidden.isEmpty ? channels : channels.filter { !hidden.contains($0.id) }
    }

    /// The guide or grid cell that last had focus, so down after Menu can land back on it.
    var focusMemory: AnyHashable?

    var isLoading: Bool { loadingFor != nil }

    static func halfHour(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 1800).rounded(.down) * 1800)
    }

    // MARK: Channels

    /// First load: the profile's lists and the EPG status, then the first page.
    func start() async {
        if !listsLoaded {
            async let lists = try? api.liveChannelLists()
            async let status = try? api.epgStatus()
            if let (fav, hid) = await lists {
                favorites = Set(fav)
                hidden = Set(hid)
                listsLoaded = true
            }
            epgEnabled = await status?.enabled ?? false
        }
        await reload()
    }

    func setSearchText(_ text: String) {
        searchText = text
        searchDebounce?.cancel()
        searchDebounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != search { search = trimmed }
        }
    }

    /// From the first page, unless the loaded list already matches the filters.
    func reload(force: Bool = false) async {
        if !force, loadedFor == query, !channels.isEmpty { return }
        channels = []
        total = nil
        hasMore = true
        loadError = nil
        loadedFor = nil
        await loadMore()
    }

    func loadMore() async {
        let requested = query
        guard hasMore, loadingFor != requested else { return }
        loadingFor = requested
        defer { if loadingFor == requested { loadingFor = nil } }
        let offset = loadedFor == requested ? channels.count : 0
        let categories = requested.filter.categories.sorted()
        let favoritesOnly = requested.filter == .favorites
        do {
            let page = try await api.liveChannels(
                sourceID: requested.sourceID, categories: categories,
                favoritesOnly: favoritesOnly, search: requested.search,
                // Sent with any other filter, the server would list favorites first (and keep
                // them in every category and search), so they go only with Favorites.
                favoriteIDs: favoritesOnly ? Array(favorites) : [], offset: offset, limit: Self.pageSize)
            guard requested == query else { return }
            var seen = Set<String>(offset == 0 ? [] : channels.map(\.id))
            let fresh = page.channels.filter { seen.insert($0.id).inserted }
            channels = offset == 0 ? fresh : channels + fresh
            hasMore = page.hasMore && !page.channels.isEmpty
            total = page.total
            if let cats = page.availableCategories { self.categories = cats }
            if let srcs = page.sources {
                sources = srcs
                if let sourceID, !srcs.contains(where: { $0.id == sourceID }) { self.sourceID = nil }
            }
            // Categories the server no longer lists drop out of the selection.
            let selected = requested.filter.categories
            if !selected.isEmpty, !self.categories.isEmpty, !selected.isSubset(of: self.categories) {
                filter = .selecting(selected.intersection(self.categories))
            }
            loadedFor = requested
            loadError = nil
        } catch {
            if channels.isEmpty, requested == query { loadError = error.localizedDescription }
        }
    }

    // MARK: Favorites and hidden channels

    /// The header's star: Favorites, or back to the filter that was on before it.
    func toggleFavoritesOnly() {
        filter = filter == .favorites ? filterBeforeFavorites : .favorites
    }

    /// Adds or removes `name` from the selected categories (from Favorites, starts a new
    /// selection); none left lists every channel.
    func toggleCategory(_ name: String) {
        var names = filter.categories
        if names.remove(name) == nil { names.insert(name) }
        filter = .selecting(names)
    }

    func toggleFavorite(_ channel: LiveChannel) {
        var fav = favorites
        if fav.contains(channel.id) { fav.remove(channel.id) } else { fav.insert(channel.id) }
        let previous = favorites
        favorites = fav
        if filter == .favorites, !fav.contains(channel.id) {
            channels.removeAll { $0.id == channel.id }
        }
        save(revert: { self.favorites = previous })
    }

    func toggleHidden(_ channel: LiveChannel) {
        var hid = hidden
        if hid.contains(channel.id) { hid.remove(channel.id) } else { hid.insert(channel.id) }
        let previous = hidden
        hidden = hid
        save(revert: { self.hidden = previous })
    }

    private func save(revert: @escaping () -> Void) {
        let fav = favorites.sorted(), hid = hidden.sorted()
        Task {
            do {
                try await api.saveLiveChannelLists(favorites: fav, hidden: hid)
                actionError = nil
            } catch {
                revert()
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: Now / next

    /// Queues `channel` for a now / next fetch (re-fetched after two minutes).
    func needNowNext(_ channel: LiveChannel) {
        guard epgEnabled == true, let key = channel.tvgId, !key.isEmpty else { return }
        if let fetched = nowNextFetched[key], Date().timeIntervalSince(fetched) < 120 { return }
        nowNextFetched[key] = Date()
        nowNextPending.insert(key)
        guard nowNextTask == nil else { return }
        nowNextTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            let keys = Array(nowNextPending)
            nowNextPending = []
            nowNextTask = nil
            for batch in stride(from: 0, to: keys.count, by: 50).map({ Array(keys[$0..<min($0 + 50, keys.count)]) }) {
                do {
                    for entry in try await api.epgNow(batch) { nowNext[entry.channelId] = entry }
                } catch {
                    batch.forEach { nowNextFetched[$0] = nil }
                }
            }
        }
    }

    /// The programme on now, from the guide data or now / next.
    func current(_ channel: LiveChannel, at now: Date = Date()) -> EPGProgram? {
        if let p = schedules[channel.guideKey]?.first(where: { $0.isAiring(at: now) }) { return p }
        if let c = nowNext[channel.guideKey]?.current, c.isAiring(at: now) { return c }
        return nil
    }

    func next(_ channel: LiveChannel, at now: Date = Date()) -> EPGProgram? {
        if let p = schedules[channel.guideKey]?.first(where: { $0.start >= now }) { return p }
        return nowNext[channel.guideKey]?.next
    }

    // MARK: Guide schedules

    /// Queues the guide chunks covering `[from, to)` for `channel`.
    func needSchedule(_ channel: LiveChannel, from: Date, to: Date) {
        guard epgEnabled == true else { return }
        let key = channel.guideKey
        let first = max(0, Int(from.timeIntervalSince(guideBase) / Self.chunk))
        let last = max(first, Int((to.timeIntervalSince(guideBase) - 1) / Self.chunk))
        var queued = false
        for index in first...last where !chunksLoaded.contains("\(index)|\(key)") {
            chunksLoaded.insert("\(index)|\(key)")
            chunksPending[index, default: []].insert(key)
            queued = true
        }
        guard queued, chunkTask == nil else { return }
        chunkTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            let pending = chunksPending
            chunksPending = [:]
            chunkTask = nil
            for (index, keys) in pending.sorted(by: { $0.key < $1.key }) {
                await fetchChunk(index, keys: Array(keys))
            }
        }
    }

    private func fetchChunk(_ index: Int, keys: [String]) async {
        let start = guideBase.addingTimeInterval(Double(index) * Self.chunk)
        let offset = Int((start.timeIntervalSinceNow / 60).rounded(.down))
        for batch in stride(from: 0, to: keys.count, by: 40).map({ Array(keys[$0..<min($0 + 40, keys.count)]) }) {
            do {
                // An hour over the chunk, so a clock skew can't leave a gap between chunks.
                let result = try await api.epgSchedule(batch, startOffsetMinutes: offset, hours: Int(Self.chunk / 3600) + 1)
                var merged = schedules
                for key in batch { merged[key] = Self.merge(merged[key] ?? [], result[key] ?? []) }
                schedules = merged
            } catch {
                batch.forEach { chunksLoaded.remove("\(index)|\($0)") }
            }
        }
    }

    /// Sorted by start, one programme per start time, each cut off where the next begins.
    private static func merge(_ old: [EPGProgram], _ new: [EPGProgram]) -> [EPGProgram] {
        var byStart: [Date: EPGProgram] = [:]
        for p in old + new where p.stop > p.start { byStart[p.start] = p }
        let sorted = byStart.values.sorted { $0.start < $1.start }
        return sorted.enumerated().map { i, p in
            guard i + 1 < sorted.count, sorted[i + 1].start < p.stop else { return p }
            var clipped = p
            clipped.stop = sorted[i + 1].start
            return clipped
        }
    }

    /// Clears the server's channel cache and reloads.
    func refresh() async {
        _ = try? await api.sendRaw("POST", "/api/live/cache/clear")
        nowNext = [:]
        nowNextFetched = [:]
        schedules = [:]
        chunksLoaded = []
        await reload(force: true)
    }
}
