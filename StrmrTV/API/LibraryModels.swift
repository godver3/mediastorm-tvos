import Foundation

// The server's local, Plex and Jellyfin libraries (`/api/library/…`). The server reads Plex
// and Jellyfin for the app and streams their files itself, so all three look the same here.

/// A configured library (`GET /api/library/libraries`).
struct LibraryInfo: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// movie | show | other
    let type: String
    /// idle | scanning | complete | failed
    let lastScanStatus: String?
    /// local | plex | jellyfin
    let sourceType: String?
    let sourceServerName: String?

    var ref: LibraryRef { LibraryRef(id: id, name: name, type: type, sourceType: sourceType) }
    var source: LibrarySource { LibrarySource(sourceType) }
    var isScanning: Bool { lastScanStatus == "scanning" }
}

/// A library as its grid and cards need it. A Home row knows only the id and its own name.
struct LibraryRef: Hashable, Sendable {
    let id: String
    let name: String
    var type: String?
    var sourceType: String?
}

/// Where a library's files live, with the Expo app's labels.
enum LibrarySource: Hashable, Sendable {
    case local, plex, jellyfin

    init(_ raw: String?) {
        switch raw?.lowercased() {
        case "plex": self = .plex
        case "jellyfin": self = .jellyfin
        default: self = .local
        }
    }

    var label: String {
        switch self {
        case .local: String(localized: "Local")
        case .plex: "Plex"
        case .jellyfin: "Jellyfin"
        }
    }
}

struct LibraryProbe: Decodable, Hashable, Sendable {
    let durationSeconds: Double?
    let videoCodec: String?
    let width: Int?
    let height: Int?
    let hdrFormat: String?
    let audioCodecs: [String]?
}

/// One file: a movie version or an episode's copy.
struct LibraryItem: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let fileName: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let episodeOverview: String?
    let episodeImage: ImageRef?
    let detectedTitle: String?
    let probe: LibraryProbe?
    let sizeBytes: Int64?
    let sourceType: String?
    let sourceServerName: String?
    /// Plex / Jellyfin's own version name ("1080p · H264").
    let versionLabel: String?
}

struct LibraryEpisode: Decodable, Hashable, Sendable {
    let episodeNumber: Int
    let episodeTitle: String?
    let episodeOverview: String?
    let episodeImage: ImageRef?
    let items: [LibraryItem]
}

struct LibrarySeason: Decodable, Hashable, Sendable {
    let seasonNumber: Int
    let episodes: [LibraryEpisode]
}

/// A title in a library: a movie with its versions, a show with its seasons, or (an "other"
/// library) a single file. `include=cards` leaves the files out.
struct LibraryGroup: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    /// title | show | file
    let groupType: String?
    /// movie | show | other
    let libraryType: String?
    let title: String
    let overview: String?
    let year: Int?
    let tmdbId: Int?
    let tvdbId: Int?
    let imdbId: String?
    let poster: ImageRef?
    let textPoster: ImageRef?
    let backdrop: ImageRef?
    let textBackdrop: ImageRef?
    let items: [LibraryItem]?
    let seasons: [LibrarySeason]?

    var isShow: Bool { groupType == "show" || libraryType == "show" }
    var hasFiles: Bool { !(items ?? []).isEmpty || !(seasons ?? []).isEmpty }
    var posterURL: String? { textPoster?.url ?? poster?.url }
    var backdropURL: String? { backdrop?.url ?? textBackdrop?.url }

    /// The catalog title the group was matched to, as the server names it (tmdb, else tvdb,
    /// else imdb); nil for unmatched files and home videos, which have no details page.
    var catalogTitleID: String? {
        if let tmdb = tmdbId, tmdb > 0 { return isShow ? "tmdb:tv:\(tmdb)" : "tmdb:movie:\(tmdb)" }
        if let tvdb = tvdbId, tvdb > 0 { return isShow ? "tvdb:series:\(tvdb)" : "tvdb:movie:\(tvdb)" }
        if let imdb = imdbId, !imdb.isEmpty { return imdb }
        return nil
    }
}

struct LibraryGroupPage: Decodable, Sendable {
    let groups: [LibraryGroup]
    let total: Int
    let alphabetBuckets: [String]?
}

/// A library's copy of a title (`GET /api/library/matches`).
struct LibraryMatch: Decodable, Sendable {
    let libraryId: String
    let libraryName: String
    let group: LibraryGroup
}

/// `GET /api/library/items/{id}/playback`: the file's stream path, played like any other.
struct LibraryPlaybackInfo: Decodable, Sendable {
    let itemId: String
    let streamPath: String
    let durationSeconds: Double?
}

/// A library title in a grid or Home row, with the library it came from.
struct LibraryEntry: Hashable, Identifiable, Sendable {
    let library: LibraryRef
    let group: LibraryGroup

    var id: String { "\(library.id)|\(group.id)" }

    /// Matched titles open their catalog details page, which finds this copy itself.
    var detailsTarget: DetailsTarget? { DetailsTarget(library: group) }
}

extension DetailsTarget {
    /// A matched library title's details page. Opened from a library, it starts no prequeue.
    init?(library group: LibraryGroup) {
        guard let titleID = group.catalogTitleID else { return nil }
        self.init(titleID: titleID, name: group.title, isMovie: !group.isShow, year: group.year,
                  tmdbID: group.tmdbId.flatMap { $0 > 0 ? String($0) : nil }, imdbID: group.imdbId,
                  tvdbID: group.tvdbId.flatMap { $0 > 0 ? String($0) : nil },
                  posterURL: group.posterURL, textPosterURL: nil, backdropURL: group.backdropURL,
                  logoURL: nil, overview: group.overview)
        fromLibrary = true
    }

    /// An unmatched library title: named by its group, keyed by nothing the catalog knows.
    init(unmatched group: LibraryGroup) {
        self.init(titleID: group.id, name: group.title, isMovie: !group.isShow, year: group.year,
                  tmdbID: nil, imdbID: nil, tvdbID: nil, posterURL: group.posterURL, textPosterURL: nil,
                  backdropURL: group.backdropURL, logoURL: nil, overview: group.overview)
        fromLibrary = true
    }

    /// Has an id the catalog knows; an unmatched library title doesn't.
    var hasCatalogIDs: Bool { tmdbID != nil || imdbID != nil || tvdbID != nil }
}
