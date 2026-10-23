import SwiftUI

/// How Home is laid out: two independent device choices. Top Carousel puts
/// a carousel of one row's titles above the rows, as on the Apple TV app's home; Focused
/// Title Info is the Classic hero, the title, line, overview and backdrop of the focused
/// card. Both default to Classic Home: no carousel, info on. The profile has no matching
/// server field, and the carousel's row defaults to Top 10 (then Trending, then the first
/// row with titles).
@MainActor
final class HomeStyleStore: ObservableObject {
    static let shared = HomeStyleStore()
    private static let log = AppLog(category: "home-carousel")

    static let defaultTopCarousel = false
    static let defaultFocusedInfo = true

    private let defaults: UserDefaults

    enum Keys {
        static let topCarousel = "homeLayout.topCarousel"
        static let focusedInfo = "homeLayout.focusedTitleInfo"
        static let carouselRow = "homeLayout.carouselRow"
        /// The first pass's single choice, Classic or Carousel; read once and removed.
        static let legacyStyle = "homeLayout.homeStyle"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrate(defaults)
        // Through the wrappers, so launch arguments aren't written back as saved settings.
        _topCarousel = Published(initialValue: defaults.object(forKey: Keys.topCarousel) as? Bool
            ?? Self.defaultTopCarousel)
        _focusedInfo = Published(initialValue: defaults.object(forKey: Keys.focusedInfo) as? Bool
            ?? Self.defaultFocusedInfo)
        _carouselRow = Published(initialValue: defaults.string(forKey: Keys.carouselRow))
    }

    /// Home Style Carousel was the carousel with plain rows: Top Carousel on, Focused Title
    /// Info off. Classic (or unset) is the defaults. Carousel Row is kept as it was.
    static func migrate(_ defaults: UserDefaults) {
        guard let legacy = defaults.string(forKey: Keys.legacyStyle) else { return }
        if legacy == "carousel" {
            defaults.set(true, forKey: Keys.topCarousel)
            defaults.set(false, forKey: Keys.focusedInfo)
        }
        defaults.removeObject(forKey: Keys.legacyStyle)
        log.info("migrated home style \(legacy)")
    }

    @Published var topCarousel: Bool {
        didSet {
            defaults.set(topCarousel, forKey: Keys.topCarousel)
            Self.log.info("top carousel \(topCarousel ? "on" : "off")")
        }
    }

    @Published var focusedInfo: Bool {
        didSet {
            defaults.set(focusedInfo, forKey: Keys.focusedInfo)
            Self.log.info("focused title info \(focusedInfo ? "on" : "off")")
        }
    }

    /// Classic Home: the defaults, drawn exactly as before the carousel.
    var isClassic: Bool { !topCarousel && focusedInfo }

    /// The shelf id the carousel shows; nil takes the default row.
    @Published var carouselRow: String? {
        didSet {
            defaults.set(carouselRow, forKey: Keys.carouselRow)
            Self.log.info("carousel row \(carouselRow ?? "default")")
        }
    }

    /// The row a Default carousel takes among the rows a profile shows.
    static func defaultRow(in shelves: [String]) -> String? {
        HomeCarouselSource.defaultRows.first(where: shelves.contains) ?? shelves.first
    }
}

/// The row the carousel shows on a Home view: the chosen one, else Top 10, else Trending,
/// else the first row with titles. A preferred row still loading holds the carousel
/// (empty) rather than letting a later choice flash in first.
struct HomeCarouselSource: Equatable {
    /// Set as soon as the row is known, so it is left out of the rows below.
    var id: String?
    var shelf: HomeShelf?

    /// The rows a Default carousel takes, in order of preference.
    static let defaultRows = ["top-ten", "trending-movies", "trending-tv"]
    /// The most titles the carousel steps through.
    static let maxSlides = 10

    static func resolve(slots: [HomeSlot], chosen: String?) -> HomeCarouselSource {
        for candidate in [chosen].compactMap { $0 } + defaultRows {
            guard let slot = slots.first(where: { $0.id == candidate }) else { continue }
            switch slot {
            case let .shelf(shelf) where !slides(shelf).isEmpty: return HomeCarouselSource(id: shelf.id, shelf: shelf)
            case .loading: return HomeCarouselSource(id: candidate, shelf: nil)
            default: continue
            }
        }
        for case let .shelf(shelf) in slots where !slides(shelf).isEmpty {
            return HomeCarouselSource(id: shelf.id, shelf: shelf)
        }
        return HomeCarouselSource()
    }

    /// The titles of a row the carousel can show: those that open a details page.
    static func slides(_ shelf: HomeShelf) -> [HomeCard] {
        Array(shelf.shown.filter { $0.target != nil }.prefix(maxSlides))
    }
}
