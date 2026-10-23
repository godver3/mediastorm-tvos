import XCTest
@testable import StrmrTV

/// The Expo app's `utils/home-views.test.ts`, plus the cases the port adds.
final class HomeViewsTests: XCTestCase {
    private func shelf(_ id: String, _ name: String = "", enabled: Bool = true, order: Int,
                       _ extra: [String: Any] = [:]) -> ShelfConfig {
        ShelfConfig.make(["id": id, "name": name, "enabled": enabled, "order": order].merging(extra) { _, new in new })!
    }

    private var base: HomeShelvesConfig {
        HomeShelvesConfig(layout: HomeLayoutConfig(shelves: [shelf("watchlist", "Saved", order: 0)], itemCap: 20))
    }

    private func enabledIDs(_ layout: HomeLayoutConfig) -> [String] {
        (layout.shelves ?? []).filter { $0.enabled == true }.map(\.id)
    }

    func testInheritsTheProfileHome() {
        let profile = HomeShelvesConfig(layout: HomeLayoutConfig(shelves: [shelf("watchlist", "Mine", order: 1)]))
        let resolved = HomeViews.resolve(global: base, profile: profile, view: "movies")
        XCTAssertEqual(resolved.shelves?.first { $0.id == "watchlist" }?.name, "Mine")
    }

    func testCustomListsReplaceAndEmptyLayoutsStayEmpty() {
        var settings = base
        settings.views = ["movies": HomeViewDefinition(mode: "custom", layout: HomeLayoutConfig(shelves: []))]
        let resolved = HomeViews.resolve(global: settings, profile: nil, view: "movies")
        XCTAssertEqual(enabledIDs(resolved), [])
        XCTAssertEqual(resolved.tvTopShelfMode, "disabled")
        // Every built-in shelf is there, disabled, so nothing fills them back in.
        XCTAssertEqual(Set(resolved.shelves?.map(\.id) ?? []), Set(HomeShelfDefaults.shelves.map(\.id)))
        XCTAssertEqual(base.layout.shelves?.first?.enabled, true)
    }

    func testProfileResetsGlobalCustomViewToItsOwnHome() {
        var settings = base
        settings.views = ["movies": HomeViewDefinition(mode: "custom", layout: HomeLayoutConfig(shelves: []))]
        let profile = HomeShelvesConfig(views: ["movies": HomeViewDefinition(mode: "inherit")])
        let resolved = HomeViews.resolve(global: settings, profile: profile, view: "movies")
        XCTAssertEqual(resolved.shelves?.first { $0.id == "watchlist" }?.enabled, true)
    }

    func testRemovesIncompatibleShelvesKeepingMixedSources() {
        var settings = base
        settings.layout.shelves?.append(shelf("trending-tv", "TV", order: 2))
        let resolved = HomeViews.resolve(global: settings, profile: nil, view: "movies")
        XCTAssertTrue(enabledIDs(resolved).contains("watchlist"))
        XCTAssertEqual(resolved.shelves?.first { $0.id == "trending-tv" }?.enabled, false)
    }

    func testNormalizesSeriesAndEpisodeTypes() {
        for type in ["tv", "series", "show", "episode"] {
            XCTAssertTrue(HomeViews.matches(mediaType: type, .shows), type)
        }
        XCTAssertTrue(HomeViews.matches(mediaType: "Movie", .movies))
        XCTAssertFalse(HomeViews.matches(mediaType: "movie", .shows))
        XCTAssertFalse(HomeViews.matches(mediaType: "channel", .shows))
        XCTAssertFalse(HomeViews.matches(mediaType: nil, .movies))
        XCTAssertTrue(HomeViews.matches(mediaType: nil, .all))
    }

    func testFallsBackToDefaultTopShelfWhenHomePromotesIncompatibleContent() {
        var settings = base
        settings.layout.tvTopShelfMode = "shelf"
        settings.layout.tvTopShelfSourceId = "dashboard"
        settings.layout.shelves?.append(shelf("dashboard", "Dashboard", order: 1))
        XCTAssertEqual(HomeViews.resolve(global: settings, profile: nil, view: "movies").tvTopShelfMode, "default")
        XCTAssertNil(HomeViews.resolve(global: settings, profile: nil, view: "movies").tvTopShelfSourceId)
        XCTAssertEqual(HomeViews.resolve(global: settings, profile: nil, view: "all").tvTopShelfMode, "shelf")
    }

    func testNamedPageInheritanceAndFilteringAreIndependent() {
        var settings = base
        settings.views = [
            "page-docs": HomeViewDefinition(name: "Documentaries", mediaFilter: "movies", mode: "inherit"),
            "page-mixed": HomeViewDefinition(name: "Mixed", mode: "custom", layout: HomeLayoutConfig(shelves: [])),
        ]
        settings.layout.shelves?.append(shelf("trending-tv", "TV", order: 2))
        let resolved = HomeViews.resolve(global: settings, profile: nil, view: "page-docs")
        XCTAssertEqual(resolved.shelves?.first { $0.id == "watchlist" }?.enabled, true)
        XCTAssertEqual(resolved.shelves?.first { $0.id == "trending-tv" }?.enabled, false)
        XCTAssertEqual(enabledIDs(HomeViews.resolve(global: settings, profile: nil, view: "page-mixed")), [])
        XCTAssertEqual(settings.layout.shelves?[1].enabled, true)

        let views = HomeViews.merge(settings.views, ["page-docs": HomeViewDefinition(mode: "custom",
                                                                                     layout: HomeLayoutConfig(shelves: []))])
        XCTAssertEqual(views["page-docs"]?.name, "Documentaries")
        XCTAssertEqual(HomeViews.filter("page-docs", views), .movies)
        let hidden = HomeViews.merge(views, ["page-docs": HomeViewDefinition(deleted: true, mode: "inherit")])
        XCTAssertFalse(HomeViews.ids(hidden).contains("page-docs"))
        XCTAssertEqual(HomeViews.filter("page-docs", hidden), .all)
    }

    func testCustomPageKeepsItsOwnShelvesAndFields() {
        var settings = base
        settings.views = ["page-test": HomeViewDefinition(name: "Test", mode: "custom", layout: HomeLayoutConfig(
            shelves: [shelf("trending-movies", order: 0), shelf("trending-tv", order: 1)], itemCap: 7))]
        let resolved = HomeViews.resolve(global: settings, profile: nil, view: "page-test")
        XCTAssertEqual(enabledIDs(resolved), ["trending-movies", "trending-tv"])
        XCTAssertEqual(resolved.itemCap, 7)
        // A built-in shelf missing from the page's list comes back disabled.
        XCTAssertEqual(resolved.shelves?.first { $0.id == "continue-watching" }?.enabled, false)
        // An inherit page keeps Home's fields.
        settings.views?["page-test"]?.mode = "inherit"
        XCTAssertEqual(HomeViews.resolve(global: settings, profile: nil, view: "page-test").itemCap, 20)
    }

    func testDeletedOrUnknownViewIsHome() {
        var settings = base
        settings.views = ["page-gone": HomeViewDefinition(name: "Gone", deleted: true, mode: "custom",
                                                           layout: HomeLayoutConfig(shelves: []))]
        XCTAssertEqual(enabledIDs(HomeViews.resolve(global: settings, profile: nil, view: "page-gone")), ["watchlist"])
    }

    func testShelfAllowed() {
        XCTAssertFalse(HomeViews.shelfAllowed(shelf("live-favorites", order: 0), .movies))
        XCTAssertFalse(HomeViews.shelfAllowed(shelf("tonight", order: 0), .shows))
        XCTAssertTrue(HomeViews.shelfAllowed(shelf("dashboard", order: 0), .all))
        XCTAssertFalse(HomeViews.shelfAllowed(shelf("my-upcoming", order: 0), .movies))
        XCTAssertTrue(HomeViews.shelfAllowed(shelf("my-upcoming", order: 0), .shows))
        XCTAssertFalse(HomeViews.shelfAllowed(shelf("genre-16-movie", order: 0), .shows))
        XCTAssertTrue(HomeViews.shelfAllowed(shelf("genre-16-tv", order: 0), .shows))
        XCTAssertFalse(HomeViews.shelfAllowed(shelf("decade-1990-tv", order: 0), .movies))
        XCTAssertFalse(HomeViews.shelfAllowed(shelf("s", order: 0, ["addonCatalogType": "series"]), .movies))
        XCTAssertTrue(HomeViews.shelfAllowed(shelf("s", order: 0, ["addonCatalogType": "", "tmdbMediaType": "movie"]), .movies))
        XCTAssertFalse(HomeViews.shelfAllowed(shelf("s", order: 0, ["simklMediaType": "movies"]), .shows))
        XCTAssertTrue(HomeViews.shelfAllowed(shelf("s", order: 0, ["tmdbMediaType": "all"]), .shows))
        XCTAssertTrue(HomeViews.shelfAllowed(shelf("mdblist-x", order: 0), .shows))
    }

    func testIDsLabelsAndParsing() {
        let views: HomeViewDefinitions = [
            "page-b": HomeViewDefinition(name: "beta"), "page-a": HomeViewDefinition(name: "Alpha"),
            "page-z": HomeViewDefinition(name: "Zed", deleted: true), "page-": HomeViewDefinition(name: "Bad"),
            "movies": HomeViewDefinition(name: "Films"),
        ]
        XCTAssertEqual(HomeViews.ids(views), ["all", "movies", "shows", "page-a", "page-b"])
        XCTAssertEqual(HomeViews.label("movies", views), "Movies")
        XCTAssertEqual(HomeViews.label("page-new", views), "Home page")
        XCTAssertEqual(HomeViews.parse("page-a"), "page-a")
        XCTAssertEqual(HomeViews.parse("page-"), "all")
        XCTAssertEqual(HomeViews.parse(nil), "all")
        XCTAssertEqual(HomeViews.parse("shows"), "shows")
        XCTAssertEqual(HomeViews.icon("shows", nil), "tv")
        XCTAssertEqual(HomeViews.icon("page-a", ["page-a": HomeViewDefinition(icon: "popcorn")]), "popcorn")
        XCTAssertEqual(HomeViews.icon("page-a", ["page-a": HomeViewDefinition(icon: "nope")]), "house")
    }

    func testMergeTakesOnlyMissingNameIconAndFilterFromGlobal() {
        let global: HomeViewDefinitions = ["page-x": HomeViewDefinition(name: "X", icon: "star", mediaFilter: "shows",
                                                                         mode: "custom", layout: HomeLayoutConfig(itemCap: 5))]
        let merged = HomeViews.merge(global, ["page-x": HomeViewDefinition(icon: "heart", mode: "inherit")])
        XCTAssertEqual(merged["page-x"]?.name, "X")
        XCTAssertEqual(merged["page-x"]?.icon, "heart")
        XCTAssertEqual(merged["page-x"]?.mediaFilter, "shows")
        XCTAssertEqual(merged["page-x"]?.mode, "inherit")
        XCTAssertNil(merged["page-x"]?.layout.itemCap)
    }

    func testDecodesViewsFromSettingsJSON() throws {
        let json = #"{"itemCap":12,"views":{"page-t":{"name":"T","mode":"custom","shelves":[],"itemCap":3},"#
            + #""shows":{"mode":"inherit"}}}"#
        let config = try JSONDecoder().decode(HomeShelvesConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.layout.itemCap, 12)
        XCTAssertEqual(config.views?["page-t"]?.layout.shelves?.count, 0)
        XCTAssertEqual(config.views?["page-t"]?.layout.itemCap, 3)
        XCTAssertNil(config.views?["shows"]?.layout.shelves)
    }
}
