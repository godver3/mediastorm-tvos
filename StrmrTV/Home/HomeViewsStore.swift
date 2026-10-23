import Combine
import Foundation

/// The profile's Home views and the one Home shows. The choice is remembered per profile on
/// this device (the Expo app resets it), falling back to All once the view is gone or
/// deleted. Each view keeps its own `HomeStore`, so switching back to one only checks
/// whether it went stale.
@MainActor
final class HomeViewsStore: ObservableObject {
    static let shared = HomeViewsStore()

    private let defaults: UserDefaults

    private enum Keys {
        /// The chosen view, by profile id.
        static let selected = "homeViews.selected"
        /// The view names and filters as last loaded, by profile id, so the menu has its
        /// labels before the server answers.
        static let cached = "homeViews.cached"
    }

    /// What the menu keeps of a view between launches.
    fileprivate struct Summary: Codable, Equatable {
        var name: String?
        var icon: String?
        var mediaFilter: String?
        var deleted: Bool?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private(set) var profileID: String?
    @Published private(set) var views: HomeViewDefinitions = [:]
    /// The view Home shows (`all` for Home itself).
    @Published private(set) var selected = HomeViews.all
    private var stores: [String: HomeStore] = [:]

    /// All, Movies, Shows and the profile's pages, in picker order.
    var ids: [String] { HomeViews.ids(views) }

    func label(_ view: String) -> String { HomeViews.label(view, views) }
    func icon(_ view: String) -> String { HomeViews.icon(view, views) }
    func filter(_ view: String) -> HomeMediaFilter { HomeViews.filter(view, views) }

    /// Switches to a profile: its remembered view and last loaded view names.
    func configure(profileID: String) {
        guard profileID != self.profileID else { return }
        self.profileID = profileID
        stores = [:]
        let cached = (defaults.dictionary(forKey: Keys.cached)?[profileID] as? Data)
            .flatMap { try? JSONDecoder().decode([String: Summary].self, from: $0) } ?? [:]
        views = cached.mapValues { HomeViewDefinition(name: $0.name, icon: $0.icon, mediaFilter: $0.mediaFilter,
                                                      deleted: $0.deleted) }
        let saved = HomeViews.parse((defaults.dictionary(forKey: Keys.selected) as? [String: String])?[profileID])
        selected = ids.contains(saved) || !HomeViews.isCustom(saved) ? saved : HomeViews.all
    }

    /// The store for a view, kept for the profile's session.
    func store(for view: String) -> HomeStore {
        if let store = stores[view] { return store }
        let store = HomeStore(view: view)
        stores[view] = store
        return store
    }

    /// Shows a view on Home and remembers it.
    func select(_ view: String) {
        let view = ids.contains(view) ? view : HomeViews.all
        if view != selected { selected = view }
        guard let profileID else { return }
        var saved = defaults.dictionary(forKey: Keys.selected) as? [String: String] ?? [:]
        saved[profileID] = view
        defaults.set(saved, forKey: Keys.selected)
    }

    /// Asks the server for the profile's views.
    func refresh() async {
        guard let views = try? await APIClient.shared.homeViews() else { return }
        update(views)
    }

    /// The views as a Home load or `refresh` read them. A view that is gone or deleted
    /// falls back to All.
    func update(_ views: HomeViewDefinitions) {
        let summaries = views.mapValues(Summary.init)
        if summaries != self.views.mapValues(Summary.init) { self.views = views }
        if let profileID, let data = try? JSONEncoder().encode(summaries) {
            var cached = defaults.dictionary(forKey: Keys.cached) ?? [:]
            cached[profileID] = data
            defaults.set(cached, forKey: Keys.cached)
        }
        if !ids.contains(selected) { select(HomeViews.all) }
    }
}

fileprivate extension HomeViewsStore.Summary {
    init(_ view: HomeViewDefinition) {
        self.init(name: view.name, icon: view.icon, mediaFilter: view.mediaFilter, deleted: view.deleted)
    }
}
