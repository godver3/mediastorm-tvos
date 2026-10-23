import Foundation

/// The Home layout fields of `homeShelves`, which a custom Home view can also set. Unset
/// fields are nil, so a view's own values can be laid over the inherited ones.
struct HomeLayoutConfig: Decodable, Sendable {
    var shelves: [ShelfConfig]?
    var itemCap: Int?
    var exploreCardPosition: String?
    var excludeUpcomingFromContinue: Bool?
    var homeShelfFocusModel: String?
    var disableTvLandscapeCardExpansion: Bool?
    var homeShelfScale: Double?
    var homeHeroScale: Double?
    var tvTopShelfMode: String?
    var tvTopShelfSourceId: String?

    init(shelves: [ShelfConfig]? = nil, itemCap: Int? = nil, tvTopShelfMode: String? = nil,
         tvTopShelfSourceId: String? = nil) {
        self.shelves = shelves
        self.itemCap = itemCap
        self.tvTopShelfMode = tvTopShelfMode
        self.tvTopShelfSourceId = tvTopShelfSourceId
    }

    /// These fields with every one `top` sets in its place (`{ ...self, ...top }`).
    func overlaid(by top: HomeLayoutConfig) -> HomeLayoutConfig {
        var result = self
        result.shelves = top.shelves ?? shelves
        result.itemCap = top.itemCap ?? itemCap
        result.exploreCardPosition = top.exploreCardPosition ?? exploreCardPosition
        result.excludeUpcomingFromContinue = top.excludeUpcomingFromContinue ?? excludeUpcomingFromContinue
        result.homeShelfFocusModel = top.homeShelfFocusModel ?? homeShelfFocusModel
        result.disableTvLandscapeCardExpansion = top.disableTvLandscapeCardExpansion ?? disableTvLandscapeCardExpansion
        result.homeShelfScale = top.homeShelfScale ?? homeShelfScale
        result.homeHeroScale = top.homeHeroScale ?? homeHeroScale
        result.tvTopShelfMode = top.tvTopShelfMode ?? tvTopShelfMode
        result.tvTopShelfSourceId = top.tvTopShelfSourceId ?? tvTopShelfSourceId
        return result
    }
}

/// `homeShelves` as the settings carry it: the layout and the view definitions.
struct HomeShelvesConfig: Decodable, Sendable {
    var layout: HomeLayoutConfig
    var views: HomeViewDefinitions?

    private enum CodingKeys: String, CodingKey { case views }

    init(layout: HomeLayoutConfig = HomeLayoutConfig(), views: HomeViewDefinitions? = nil) {
        self.layout = layout
        self.views = views
    }

    init(from decoder: Decoder) throws {
        layout = try HomeLayoutConfig(from: decoder)
        views = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(HomeViewDefinitions.self, forKey: .views)
    }
}

extension HomeViews {
    /// The layout a view shows (the Expo app's `resolveHomeViewSettings`). All is Home as
    /// configured. Another view inherits Home unless it is a custom page, whose fields
    /// replace Home's; an empty custom shelf list is an intentionally empty page (and turns
    /// the top shelf off), no list inherits Home's. A top shelf the view's filter can't show
    /// falls back to the default; built-in shelves missing from a custom list come back
    /// disabled, and shelves of the wrong media type are disabled.
    ///
    /// `global` is the server's `homeShelves`, `profile` the profile's. A profile shelf
    /// replaces the server's shelf of the same ID whole (Expo merges their fields; the
    /// profile settings the server returns already carry them).
    static func resolve(global: HomeShelvesConfig?, profile: HomeShelvesConfig?, view: String) -> HomeLayoutConfig {
        var base = (global?.layout ?? HomeLayoutConfig()).overlaid(by: profile?.layout ?? HomeLayoutConfig())
        base.shelves = mergeShelves(global?.layout.shelves ?? [], profile?.layout.shelves)
        if view == all { return base }
        let views = merge(global?.views, profile?.views)
        let override = views[view]
        if override?.deleted == true { return base }
        let filter = filter(view, views)
        var inherited = base
        inherited.shelves = HomeShelfDefaults.ensure(base.shelves ?? [])
        let custom = override?.mode == "custom"
        var resolved = custom ? inherited.overlaid(by: override!.layout) : inherited
        if custom, override?.layout.shelves?.isEmpty == true {
            resolved.tvTopShelfMode = override?.layout.tvTopShelfMode ?? "disabled"
        }
        if resolved.tvTopShelfMode == "shelf" {
            let source = resolved.shelves?.first { $0.id == resolved.tvTopShelfSourceId }
            if source.map({ !shelfAllowed($0, filter) }) ?? true {
                resolved.tvTopShelfMode = "default"
                resolved.tvTopShelfSourceId = nil
            }
        }
        let own = resolved.shelves ?? []
        let shelves = !own.isEmpty || override?.layout.shelves != nil ? own : HomeShelfDefaults.shelves
        // Disabled stand-ins keep built-in rows from being filled back in.
        let ids = Set(shelves.map(\.id))
        let missing = HomeShelfDefaults.shelves.filter { !ids.contains($0.id) }.map { $0.with(enabled: false) }
        resolved.shelves = (shelves + missing).map { shelfAllowed($0, filter) ? $0 : $0.with(enabled: false) }
        return resolved
    }

    /// The profile's shelves, then the server's that the profile doesn't have
    /// (`mergeHomeShelvesWithGlobal`); no profile list means the server's.
    static func mergeShelves(_ global: [ShelfConfig], _ profile: [ShelfConfig]?) -> [ShelfConfig] {
        guard let profile else { return global }
        if global.isEmpty { return profile }
        let ids = Set(profile.map(\.id))
        return profile + global.filter { !ids.contains($0.id) }
    }
}

extension ShelfConfig {
    func with(enabled: Bool) -> ShelfConfig {
        var copy = self
        copy.enabled = enabled
        return copy
    }

    /// A shelf the app adds itself, decoded like a configured one.
    static func make(_ fields: [String: Any]) -> ShelfConfig? {
        (try? JSONSerialization.data(withJSONObject: fields)).flatMap { try? JSONDecoder().decode(ShelfConfig.self, from: $0) }
    }
}
