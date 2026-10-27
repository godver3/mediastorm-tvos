import SwiftUI

/// Where the focused card sits in a Home row once the row has scrolled to it
/// (`homeShelfFocusModel` in the Expo app).
enum FocusedCardPosition: String, CaseIterable, Identifiable, Sendable {
    case left, center, right

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        }
    }
}

/// How much of Home the hero (logo, episode line, overview) takes above the rows.
enum HeroSize: String, CaseIterable, Identifiable, Sendable {
    /// Logo, line and a three-line overview; one row below.
    case full
    /// A smaller logo and a two-line overview; more room for rows.
    case compact
    /// The title and its line only.
    case minimal
    /// No hero text; the backdrop still follows focus.
    case off

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .full: "Full"
        case .compact: "Compact"
        case .minimal: "Minimal"
        case .off: "Off"
        }
    }

    /// The size nearest the profile's `homeHeroScale` (0.5–1, which in the Expo app
    /// shrinks the hero area).
    init(profileScale scale: Double) {
        self = scale >= 0.9 ? .full : scale >= 0.7 ? .compact : .minimal
    }
}

/// The hero's text size.
enum HeroTextSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.15
        }
    }
}

/// The size of Home's cards (and so of its rows).
enum CardSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    var scale: Double {
        switch self {
        case .small: 0.6
        case .medium: 0.8
        case .large: 1
        // A Large poster is 180 × 270; Extra Large 225 × 338.
        case .extraLarge: 1.25
        }
    }

    /// The size nearest a scale, for naming the profile's `homeShelfScale`.
    init(nearest scale: Double) {
        self = Self.allCases.min { abs($0.scale - scale) < abs($1.scale - scale) } ?? .large
    }
}

/// How a Home row draws its cards.
enum ShelfStyle: String, CaseIterable, Identifiable, Sendable {
    /// 2:3 posters.
    case poster
    /// 2:3 posters; the focused one opens to a 16:9 card with the title's backdrop
    /// (the Expo TV home's `tvLandscapeOnFocus`).
    case expandingPoster
    /// 16:9 cards.
    case landscape

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .poster: "Poster"
        case .expandingPoster: "Poster, Expands on Focus"
        case .landscape: "Landscape"
        }
    }

    /// The Home Layout setting sizing this kind of row's cards.
    var cardSizeTitle: LocalizedStringKey {
        switch self {
        case .poster: "Poster Cards"
        case .expandingPoster: "Expanding Poster Cards"
        case .landscape: "Landscape Cards"
        }
    }

    /// Shelves the Expo TV home draws landscape (`cardLayout: 'landscape'` in
    /// `useTVHomeShelves`); the rest are posters.
    static func isLandscapeByDefault(_ config: ShelfConfig) -> Bool {
        landscapeShelfIDs.contains(config.id) || config.type == "collection-hub"
    }

    private static let landscapeShelfIDs: Set<String> = [
        HomeShelf.continueWatchingID, "my-upcoming", "watch-something", "dashboard", "streaming-services",
        "recently-watched", "watch-together", "tonight", "live-favorites",
    ]
}

/// A Home row the profile shows, for the per-shelf settings.
struct ShelfLayoutInfo: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let landscapeByDefault: Bool
}

/// The Home layout values the profile's `homeShelves` settings carry (set in the Expo app
/// or the admin UI). The device settings override each one.
struct ProfileHomeLayout: Equatable, Sendable {
    /// `homeShelfFocusModel`; left when unset.
    var focusPosition: FocusedCardPosition = .left
    /// Poster rows open the focused card to 16:9 (`!disableTvLandscapeCardExpansion`).
    var expandPosters = true
    /// `homeShelfScale`, 0.5–1.
    var cardScale = 1.0
    /// `homeHeroScale`, 0.5–1.
    var heroScale = 1.0

    init() {}

    init(focusModel: String?, disableCardExpansion: Bool?, shelfScale: Double?, heroScale: Double?) {
        focusPosition = focusModel.flatMap(FocusedCardPosition.init(rawValue:)) ?? .left
        expandPosters = disableCardExpansion != true
        cardScale = Self.clamp(shelfScale)
        self.heroScale = Self.clamp(heroScale)
    }

    /// As the Expo app reads the scales: unset or non-positive is 1, else 0.5–1.
    private static func clamp(_ scale: Double?) -> Double {
        guard let scale, scale.isFinite, scale > 0 else { return 1 }
        return min(max(scale, 0.5), 1)
    }

    var heroSize: HeroSize { HeroSize(profileScale: heroScale) }
}

/// The Home layout choices made on this device, saved locally, on top of the profile's
/// values. A nil choice follows the profile.
@MainActor
final class HomeLayoutStore: ObservableObject {
    static let shared = HomeLayoutStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Through the wrappers: a plain assignment here runs `didSet`, which wrote launch
        // argument values (`-homeLayout.focusPosition right`) back as saved settings.
        _focusPosition = Published(initialValue: defaults.string(forKey: Keys.focusPosition)
            .flatMap(FocusedCardPosition.init(rawValue:)))
        _expandPosters = Published(initialValue: Self.bool(defaults, Keys.expandPosters))
        _heroSize = Published(initialValue: defaults.string(forKey: Keys.heroSize).flatMap(HeroSize.init(rawValue:)))
        _heroTextSize = Published(initialValue: defaults.string(forKey: Keys.heroTextSize)
            .flatMap(HeroTextSize.init(rawValue:)) ?? .medium)
        // The earlier on / off "Titles Under Cards" switch: off carries over as None.
        _cardText = Published(initialValue: defaults.string(forKey: Keys.cardText).flatMap(CardText.init(rawValue:))
            ?? (Self.bool(defaults, Keys.cardTitles) == false ? CardText.off : nil))
        _cardSize = Published(initialValue: defaults.string(forKey: Keys.cardSize).flatMap(CardSize.init(rawValue:)))
        let sizes = defaults.dictionary(forKey: Keys.styleCardSizes) as? [String: String] ?? [:]
        _styleCardSizes = Published(initialValue: Dictionary(uniqueKeysWithValues: sizes.compactMap { style, size in
            ShelfStyle(rawValue: style).flatMap { style in CardSize(rawValue: size).map { (style, $0) } }
        }))
        let saved = defaults.dictionary(forKey: Keys.shelfStyles) as? [String: String] ?? [:]
        _shelfStyles = Published(initialValue: saved.compactMapValues(ShelfStyle.init(rawValue:)))
        _hiddenShelves = Published(initialValue: Set(defaults.stringArray(forKey: Keys.hiddenShelves) ?? []))
        _viewSwitcher = Published(initialValue: Self.bool(defaults, Keys.viewSwitcher) ?? false)
    }

    /// A saved Bool, or nil when unset. `bool(forKey:)` also reads launch arguments
    /// ("-homeLayout.cardTitles 0"), which arrive as strings.
    private static func bool(_ defaults: UserDefaults, _ key: String) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }

    private enum Keys {
        static let focusPosition = "homeLayout.focusPosition"
        static let expandPosters = "homeLayout.expandPosters"
        static let shelfStyles = "homeLayout.shelfStyles"
        static let hiddenShelves = "homeLayout.hiddenShelves"
        static let heroSize = "homeLayout.heroSize"
        static let heroTextSize = "homeLayout.heroTextSize"
        static let cardSize = "homeLayout.cardSize"
        static let styleCardSizes = "homeLayout.styleCardSizes"
        static let cardTitles = "homeLayout.cardTitles"
        static let cardText = "homeLayout.cardText"
        static let viewSwitcher = "homeLayout.viewSwitcher"
    }

    /// The profile's values, as Home last loaded them.
    @Published private(set) var profile = ProfileHomeLayout()

    @Published var focusPosition: FocusedCardPosition? {
        didSet { defaults.set(focusPosition?.rawValue, forKey: Keys.focusPosition) }
    }

    var effectiveFocusPosition: FocusedCardPosition { focusPosition ?? profile.focusPosition }

    /// Whether poster rows without their own style expand the focused card.
    @Published var expandPosters: Bool? {
        didSet { defaults.set(expandPosters, forKey: Keys.expandPosters) }
    }

    var effectiveExpandPosters: Bool { expandPosters ?? profile.expandPosters }

    @Published var heroSize: HeroSize? {
        didSet { defaults.set(heroSize?.rawValue, forKey: Keys.heroSize) }
    }

    var effectiveHeroSize: HeroSize { heroSize ?? profile.heroSize }

    /// Device only: the profile has no hero text size.
    @Published var heroTextSize: HeroTextSize {
        didSet { defaults.set(heroTextSize.rawValue, forKey: Keys.heroTextSize) }
    }

    @Published var cardSize: CardSize? {
        didSet { defaults.set(cardSize?.rawValue, forKey: Keys.cardSize) }
    }

    /// Where the cards' title and line go (device only). The profile has no such field,
    /// so Default is Below; Overlay and None fit more rows.
    @Published var cardText: CardText? {
        didSet {
            defaults.set(cardText?.rawValue, forKey: Keys.cardText)
            defaults.removeObject(forKey: Keys.cardTitles)
        }
    }

    static let defaultCardText = CardText.below
    var effectiveCardText: CardText { cardText ?? Self.defaultCardText }

    /// The View Switcher pill under the tab bar, which opens the Home View picker (device
    /// only, off by default).
    @Published var viewSwitcher: Bool {
        didSet { defaults.set(viewSwitcher, forKey: Keys.viewSwitcher) }
    }

    /// The card scale: the device's size, else the profile's own scale (not rounded to a size).
    var effectiveCardScale: Double { cardSize?.scale ?? profile.cardScale }

    /// Card sizes chosen for one kind of row (device only); a kind not listed takes Card Size.
    @Published var styleCardSizes: [ShelfStyle: CardSize] {
        didSet {
            defaults.set(Dictionary(uniqueKeysWithValues: styleCardSizes.map { ($0.key.rawValue, $0.value.rawValue) }),
                         forKey: Keys.styleCardSizes)
        }
    }

    /// The card scale of rows drawn in a style: its own size, else Card Size's.
    func cardScale(for style: ShelfStyle) -> Double { styleCardSizes[style]?.scale ?? effectiveCardScale }

    /// Card styles chosen for single rows, by shelf id (rows not listed use their default).
    @Published private(set) var shelfStyles: [String: ShelfStyle] {
        didSet { defaults.set(shelfStyles.mapValues(\.rawValue), forKey: Keys.shelfStyles) }
    }

    /// The rows the profile shows, as Home last loaded them.
    @Published private(set) var shelves: [ShelfLayoutInfo] = []
    private var landscapeByDefault: Set<String> = []

    /// A row's default style: landscape where the Expo app draws landscape, else posters
    /// (expanding or not, per `effectiveExpandPosters`).
    func defaultStyle(for shelf: String) -> ShelfStyle {
        if landscapeByDefault.contains(shelf) { return .landscape }
        return effectiveExpandPosters ? .expandingPoster : .poster
    }

    func style(for shelf: String) -> ShelfStyle { shelfStyles[shelf] ?? defaultStyle(for: shelf) }

    /// Sets a row's style; nil returns it to the default.
    func setStyle(_ style: ShelfStyle?, for shelf: String) { shelfStyles[shelf] = style }

    /// Rows hidden from Home on this device, by shelf id. They still load, so showing one
    /// again is immediate.
    @Published private(set) var hiddenShelves: Set<String> {
        didSet { defaults.set(hiddenShelves.sorted(), forKey: Keys.hiddenShelves) }
    }

    func isHidden(_ shelf: String) -> Bool { hiddenShelves.contains(shelf) }

    func setHidden(_ hidden: Bool, for shelf: String) {
        if hidden { hiddenShelves.insert(shelf) } else { hiddenShelves.remove(shelf) }
    }

    /// Returns every row to its default style and shows any hidden ones.
    func resetShelfStyles() {
        shelfStyles = [:]
        hiddenShelves = []
    }

    /// Called by Home after loading the profile's settings and planning its rows.
    func update(profile: ProfileHomeLayout, shelves: [ShelfLayoutInfo]) {
        if profile != self.profile { self.profile = profile }
        if shelves != self.shelves {
            self.shelves = shelves
            landscapeByDefault = Set(shelves.filter(\.landscapeByDefault).map(\.id))
        }
    }
}

/// Where the cards of one Home row sit, for scrolling it: every card has the same
/// width except the focused one, which can be wider (a poster, or the explore card, that
/// opens to 16:9).
struct RowMetrics: Equatable {
    var count: Int
    var cardWidth: CGFloat
    /// The focused card's width; the same as `cardWidth` unless cards expand on focus.
    var focusedWidth: CGFloat
    var spacing: CGFloat
    var position: FocusedCardPosition

    var stride: CGFloat { cardWidth + spacing }

    func width(focusing index: Int) -> CGFloat { focusedWidth }

    /// The row's scroll position (`ScrollPosition.scrollTo(x:)`, which counts from the
    /// first card, inside the content margins) that puts the card at `index`, focused,
    /// where the setting says, within the `container` width between the margins.
    /// Clamped, so the row stays put at its start and stops at its end.
    func offset(focusing index: Int, container: CGFloat) -> CGFloat {
        let width = width(focusing: index)
        let leading = CGFloat(index) * stride
        let x = switch position {
        case .left: leading
        case .center: leading + width / 2 - container / 2
        case .right: leading + width - container
        }
        let content = CGFloat(count) * cardWidth + CGFloat(max(count - 1, 0)) * spacing + (width - cardWidth)
        return min(max(x, 0), max(0, content - container))
    }
}
