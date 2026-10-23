import Foundation

/// What the long-press menus and the details page need to know about a title beyond the
/// watchlist: hidden from the profile, Set Aside, in Continue Watching, watched (movies).
/// One per profile, shared by every tab, as the Expo app's HiddenItems / SetAside /
/// WatchStatus contexts are. Actions live in `TitleStateStore+Actions`.
@MainActor
final class TitleStateStore: ObservableObject {
    /// The reserved custom list Continue Watching titles are parked in (Expo's `SET_ASIDE_LIST_NAME`).
    static let setAsideListName = "Set Aside"

    // Internal set for `+Actions`.
    @Published var hidden: [HiddenItem] = []
    @Published var hiddenLoaded = false
    @Published var setAside: [WatchlistItem] = []
    @Published var setAsideListID: String?
    @Published var continueWatching: [ContinueWatchingItem] = []
    @Published var watchedKeys: Set<String> = []
    /// A short confirmation ("Hidden from this profile"), shown over the tabs for a moment.
    @Published var toast: String?
    /// A series whose bulk watch-state screen a card's long press opened.
    @Published var watchStateTarget: DetailsTarget?

    let log = AppLog(category: "titles")
    let api = APIClient.shared
    private var toastClear: Task<Void, Never>?

    func refresh() async {
        async let a: Void = refreshHidden()
        async let b: Void = refreshSetAside()
        async let c: Void = refreshContinueWatching()
        async let d: Void = refreshWatched()
        _ = await (a, b, c, d)
    }

    func refreshHidden() async {
        guard let items = try? await api.hiddenItems() else { return }
        hidden = items
        hiddenLoaded = true
    }

    func refreshSetAside() async {
        guard let lists = try? await api.customLists() else { return }
        guard let list = lists.first(where: \.isSetAside) else {
            setAsideListID = nil
            setAside = []
            return
        }
        setAsideListID = list.id
        if let items = try? await api.customListItems(id: list.id) { setAside = items }
    }

    func refreshContinueWatching() async {
        if let items = try? await api.continueWatching() { continueWatching = items }
    }

    func refreshWatched() async {
        if let keys = try? await api.watchedKeys() { watchedKeys = keys }
    }

    // MARK: State

    /// Hidden from this profile: any shared identity token, as Expo's `isHidden`.
    func isHidden(_ target: DetailsTarget) -> Bool { hiddenItem(target) != nil }

    func hiddenItem(_ target: DetailsTarget) -> HiddenItem? {
        let mine = Self.tokens(mediaType: target.isMovie ? "movie" : "series", id: target.titleID,
                               externalIDs: target.watchlistUpsert.externalIds ?? [:])
        return hidden.first { item in
            !Self.tokens(mediaType: item.mediaType, id: item.id, externalIDs: item.externalIds ?? [:]).isDisjoint(with: mine)
        }
    }

    func setAsideItem(_ target: DetailsTarget) -> WatchlistItem? {
        setAside.first { WatchlistStore.matches($0, target) }
    }

    /// In Continue Watching (which already leaves out Set Aside titles).
    func inContinueWatching(_ target: DetailsTarget) -> Bool { continueWatchingItem(target) != nil }

    func continueWatchingItem(_ target: DetailsTarget) -> ContinueWatchingItem? {
        continueWatching.first { item in
            guard item.isMovie == target.isMovie else { return false }
            if item.seriesId.caseInsensitiveCompare(target.titleID) == .orderedSame { return true }
            let ids = item.externalIds ?? [:]
            return [("tmdb", target.tmdbID), ("imdb", target.imdbID), ("tvdb", target.tvdbID)].contains { key, value in
                guard let value, !value.isEmpty else { return false }
                return ids[key]?.caseInsensitiveCompare(value) == .orderedSame
            }
        }
    }

    /// A movie in the profile's watched history, by any of its identity keys.
    func isWatched(movie target: DetailsTarget) -> Bool {
        var ids = [target.titleID]
        if let v = target.tmdbID { ids.append("tmdb:movie:\(v)") }
        if let v = target.imdbID { ids.append(v) }
        if let v = target.tvdbID { ids.append("tvdb:movie:\(v)") }
        return ids.contains { watchedKeys.contains("movie:\($0.lowercased())") }
    }

    func show(toast text: String) {
        toast = text
        toastClear?.cancel()
        toastClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    // MARK: Identity tokens (Expo HiddenItemsContext)

    nonisolated static func tokens(mediaType: String, id: String, externalIDs: [String: String]) -> Set<String> {
        let lowered = mediaType.lowercased().trimmingCharacters(in: .whitespaces)
        let type = (lowered == "tv" || lowered == "show") ? "series" : lowered
        var tokens = Set<String>()
        func add(_ value: String) {
            let v = value.trimmingCharacters(in: .whitespaces).lowercased()
            if !type.isEmpty, !v.isEmpty { tokens.insert("\(type):\(v)") }
        }
        func addProvider(_ provider: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespaces).lowercased()
            guard !type.isEmpty, !provider.isEmpty, !v.isEmpty else { return }
            tokens.insert("\(type):\(provider):\(v)")
            tokens.insert("\(type):\(v)")
        }
        let raw = id.trimmingCharacters(in: .whitespaces).lowercased()
        if !raw.isEmpty {
            add(raw)
            for (pattern, provider) in [(#"^tmdb:(?:movie|tv):(.+)$"#, "tmdb"), (#"^tvdb:(?:movie|series):(.+)$"#, "tvdb"),
                                        (#"^(?:imdb:)?(tt\d+)$"#, "imdb")] {
                if let match = raw.firstMatch(of: try! Regex(pattern)), let value = match.output[1].substring {
                    addProvider(provider, String(value))
                }
            }
        }
        for (key, value) in externalIDs { addProvider(key.lowercased(), value) }
        return tokens
    }
}

extension Notification.Name {
    /// A title was hidden or unhidden, set aside, or marked watched: rows and grids reload.
    static let titleStateChanged = Notification.Name("StrmrTV.titleStateChanged")
}
