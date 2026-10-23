import Foundation

/// A Top Shelf link: `com.strmr.app.nx://details?…` opens a title's details page and
/// `com.strmr.app.nx://play?…` opens it and starts its primary action (Resume / Play).
/// The query carries enough of the title for details to draw before its bundle loads.
struct DeepLink: Equatable {
    static let scheme = "com.strmr.app.nx"

    enum Action: String { case details, play }

    let action: Action
    let target: DetailsTarget

    init(action: Action, target: DetailsTarget) {
        self.action = action
        self.target = target
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme, let action = Action(rawValue: url.host() ?? ""),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var q: [String: String] = [:]
        for item in components.queryItems ?? [] { if let v = item.value, !v.isEmpty { q[item.name] = v } }
        guard let id = q["titleId"], let name = q["name"] else { return nil }
        self.action = action
        target = DetailsTarget(titleID: id, name: name, isMovie: q["mediaType"] == "movie",
                               year: q["year"].flatMap(Int.init), tmdbID: q["tmdb"], imdbID: q["imdb"],
                               tvdbID: q["tvdb"], posterURL: q["poster"], textPosterURL: q["textPoster"],
                               backdropURL: q["backdrop"], logoURL: q["logo"], overview: nil)
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = action.rawValue
        let t = target
        let fields: [(String, String?)] = [
            ("titleId", t.titleID), ("name", t.name), ("mediaType", t.isMovie ? "movie" : "series"),
            ("year", t.year.map(String.init)), ("tmdb", t.tmdbID), ("imdb", t.imdbID), ("tvdb", t.tvdbID),
            ("poster", t.posterURL), ("textPoster", t.textPosterURL), ("backdrop", t.backdropURL), ("logo", t.logoURL),
        ]
        components.queryItems = fields.compactMap { name, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: name, value: value)
        }
        return components.url
    }
}

/// Holds a link that arrived before the main tabs could take it (cold launch, sign-in,
/// profile picker), and the title whose details page should start playing on load.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    private static let log = AppLog(category: "deeplink")

    @Published var pending: DeepLink?
    /// The title a play link opened, until its details page starts playback. Published so
    /// a details page already showing that title (same path, no reload) still sees it.
    @Published private(set) var autoplayTitleID: String?
    private var autoplayArmed = Date.distantPast
    /// A details page that never loads must not start playing on a later, unrelated visit.
    private static let autoplayWindow: TimeInterval = 60

    func open(_ url: URL) {
        guard let link = DeepLink(url) else {
            Self.log.error("unhandled URL \(url.absoluteString)")
            return
        }
        Self.log.info("\(link.action.rawValue) \(link.target.titleID)")
        pending = link
    }

    /// Takes the pending link, arming autoplay for a play link.
    func take() -> DeepLink? {
        guard let link = pending else { return nil }
        pending = nil
        autoplayTitleID = link.action == .play ? link.target.titleID : nil
        autoplayArmed = .now
        return link
    }

    /// Has the next details page for `titleID` start playing once it loads, as a play link
    /// does (the Home carousel's Play).
    func armAutoplay(_ titleID: String) {
        autoplayTitleID = titleID
        autoplayArmed = .now
    }

    /// True once, for the details page a play link opened.
    func consumeAutoplay(_ titleID: String) -> Bool {
        guard autoplayTitleID == titleID else { return false }
        autoplayTitleID = nil
        return Date.now.timeIntervalSince(autoplayArmed) < Self.autoplayWindow
    }
}
