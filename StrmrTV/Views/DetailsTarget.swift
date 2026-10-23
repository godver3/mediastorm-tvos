import Foundation

/// Navigation value for the details screen; built from either a continue-watching
/// row or a search result, so details can render immediately before metadata loads.
struct DetailsTarget: Hashable {
    let titleID: String
    let name: String
    let isMovie: Bool
    let year: Int?
    let tmdbID: String?
    let imdbID: String?
    let tvdbID: String?
    let posterURL: String?
    /// The poster with its title text, when the server's `posterURL` is textless.
    let textPosterURL: String?
    let backdropURL: String?
    /// Known up front from Continue Watching and search, so details can show it at once.
    let logoURL: String?
    let overview: String?

    init(titleID: String, name: String, isMovie: Bool, year: Int?, tmdbID: String?, imdbID: String?,
         tvdbID: String?, posterURL: String?, textPosterURL: String?, backdropURL: String?,
         logoURL: String?, overview: String?) {
        self.titleID = titleID
        self.name = name
        self.isMovie = isMovie
        self.year = year
        self.tmdbID = tmdbID
        self.imdbID = imdbID
        self.tvdbID = tvdbID
        self.posterURL = posterURL
        self.textPosterURL = textPosterURL
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.overview = overview
    }

    init(_ item: ContinueWatchingItem) {
        titleID = item.seriesId
        name = item.seriesTitle
        isMovie = item.isMovie
        year = item.year
        tmdbID = item.externalIds?["tmdb"]
        imdbID = item.externalIds?["imdb"]
        tvdbID = item.externalIds?["tvdb"]
        posterURL = item.posterUrl
        textPosterURL = item.textPosterUrl
        backdropURL = item.backdropUrl
        logoURL = item.logoUrl
        overview = item.overview
    }

    init(_ item: WatchlistItem) {
        titleID = item.id
        name = item.name
        isMovie = item.isMovie
        year = item.year
        tmdbID = item.externalIds?["tmdb"]
        imdbID = item.externalIds?["imdb"]
        tvdbID = item.externalIds?["tvdb"]
        posterURL = item.posterUrl
        textPosterURL = item.textPosterUrl
        backdropURL = item.backdropUrl
        logoURL = item.logoUrl
        overview = item.overview
    }

    init(_ item: HiddenItem) {
        titleID = item.id
        name = item.name ?? item.id
        isMovie = item.isMovie
        year = item.year
        tmdbID = item.externalIds?["tmdb"]
        imdbID = item.externalIds?["imdb"]
        tvdbID = item.externalIds?["tvdb"]
        posterURL = item.posterUrl
        textPosterURL = nil
        backdropURL = item.backdropUrl
        logoURL = nil
        overview = nil
    }

    init(_ title: Title) {
        titleID = title.id
        name = title.name
        isMovie = title.isMovie
        year = title.year
        tmdbID = title.tmdbId.map(String.init)
        imdbID = title.imdbId
        tvdbID = title.tvdbId.map(String.init)
        posterURL = title.poster?.url
        textPosterURL = title.textPoster?.url
        backdropURL = title.backdrop?.url
        logoURL = title.logo?.url
        overview = title.overview
    }

    /// Portrait cards show the poster with its title text: the server may swap in a
    /// textless poster, and these cards draw no title of their own.
    var displayPosterURL: String? { textPosterURL ?? posterURL }
}

enum Artwork {
    /// TMDB "original" backdrops are multi-megabyte; w1280 is plenty for a 1080p UI.
    static func url(_ raw: String?, size: String = "w1280") -> URL? {
        guard let raw else { return nil }
        return raw.replacingOccurrences(of: "/t/p/original/", with: "/t/p/\(size)/").asURL
    }

    /// A title logo. TMDB serves some logos as SVG, which UIImage cannot draw; the same
    /// path with `.png` comes back rasterized.
    static func logoURL(_ raw: String?, size: String = "original") -> URL? {
        guard var raw else { return nil }
        if raw.lowercased().hasSuffix(".svg"), raw.contains("image.tmdb.org") {
            raw = String(raw.dropLast(4)) + ".png"
        }
        return url(raw, size: size)
    }
}

func formatTimestamp(_ seconds: Double) -> String {
    let s = Int(seconds)
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}
