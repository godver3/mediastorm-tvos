#if os(iOS)
import Foundation

/// One offline download: what it is (the title's ids, for playback and progress reports), where
/// it comes from (the server stream path) and where it is going (a file in `DownloadStorage`).
/// Persisted as JSON by `DownloadManager`, the Expo app's `DownloadItem`.
struct DownloadItem: Codable, Identifiable, Hashable {
    enum Status: String, Codable {
        /// Queued: waiting for a free slot, for Wi-Fi, or for the server.
        case pending
        case downloading
        case paused
        case completed
        case failed
    }

    /// Why a pending download is not running yet.
    enum WaitingReason: String, Codable {
        case wifi
        case server
    }

    let id: String
    let createdAt: Date

    // The title
    let titleID: String
    let isMovie: Bool
    let name: String
    let year: Int?
    let tmdbID: String?
    let imdbID: String?
    let tvdbID: String?
    let posterURL: String?
    let backdropURL: String?
    let overview: String?

    // The episode (series only)
    var seasonNumber: Int?
    var episodeNumber: Int?
    var episodeName: String?
    var episodeOverview: String?
    /// The server's canonical progress item ID, from `/details-bundle`.
    var episodeItemID: String?

    // The source
    let streamPath: String
    let releaseName: String?
    /// Size reported by the indexer / debrid provider; replaced by the response's length.
    var expectedBytes: Int64
    let fileName: String

    // Transfer state
    var status: Status = .pending
    var bytesWritten: Int64 = 0
    var waitingReason: WaitingReason?
    var errorMessage: String?
    var completedAt: Date?
    /// Not persisted in spirit (reset on launch); bytes per second while downloading.
    var bytesPerSecond: Double = 0

    var isEpisode: Bool { !isMovie }
    var isActive: Bool { status == .pending || status == .downloading || status == .paused }

    var progress: Double {
        guard expectedBytes > 0 else { return status == .completed ? 1 : 0 }
        return min(max(Double(bytesWritten) / Double(expectedBytes), 0), 1)
    }

    var episodeCode: String? {
        guard let seasonNumber, let episodeNumber else { return nil }
        return String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    /// "Show · S01E02" for an episode, the title for a movie.
    var displayTitle: String {
        guard let episodeCode else { return name }
        return "\(name) · \(episodeCode)"
    }

    /// The row's main line: an episode's name (or code), a movie's title.
    var rowTitle: String {
        guard isEpisode else { return name }
        if let episodeName, !episodeName.isEmpty { return episodeName }
        return episodeCode.map { String(localized: "Episode \($0)") } ?? name
    }

    /// Groups a show's episodes in the list.
    var showKey: String { titleID }

    /// Matches a details page's movie, or one of its episodes.
    func matches(titleID: String, season: Int?, episode: Int?) -> Bool {
        guard self.titleID == titleID else { return false }
        if isMovie { return season == nil }
        return seasonNumber == season && episodeNumber == episode
    }

    var target: DetailsTarget {
        DetailsTarget(titleID: titleID, name: name, isMovie: isMovie, year: year, tmdbID: tmdbID, imdbID: imdbID,
                      tvdbID: tvdbID, posterURL: posterURL, textPosterURL: nil, backdropURL: backdropURL,
                      logoURL: nil, overview: overview)
    }

    /// The progress record's item ID, for the resume lookup: the movie's title ID, an episode's
    /// server item ID, else the `{series}:SxxEyy` form the server derives.
    var progressItemID: String {
        if isMovie { return titleID }
        return episodeItemID ?? "\(titleID):\(episodeCode ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, titleID, isMovie, name, year, tmdbID, imdbID, tvdbID, posterURL, backdropURL, overview
        case seasonNumber, episodeNumber, episodeName, episodeOverview, episodeItemID
        case streamPath, releaseName, expectedBytes, fileName
        case status, bytesWritten, waitingReason, errorMessage, completedAt
    }
}

extension DownloadItem {
    /// A new record for a title (and episode) at `streamPath`.
    init(target: DetailsTarget, episode: Episode?, streamPath: String, releaseName: String?, expectedBytes: Int64) {
        let id = UUID().uuidString.lowercased()
        self.id = id
        createdAt = Date()
        titleID = target.titleID
        isMovie = target.isMovie
        name = target.name
        year = target.year
        tmdbID = target.tmdbID
        imdbID = target.imdbID
        tvdbID = target.tvdbID
        posterURL = target.posterURL
        backdropURL = target.backdropURL
        overview = target.overview
        seasonNumber = episode?.seasonNumber
        episodeNumber = episode?.episodeNumber
        episodeName = episode?.name
        episodeOverview = episode?.overview
        episodeItemID = episode?.itemId
        self.streamPath = streamPath
        self.releaseName = releaseName
        self.expectedBytes = expectedBytes
        fileName = "\(id).\(Self.fileExtension(streamPath))"
    }

    /// The container's extension from the stream path (`mkv` when it has none we know).
    static func fileExtension(_ path: String) -> String {
        let last = (path.removingPercentEncoding ?? path).split(separator: "/").last.map(String.init) ?? ""
        let ext = (last as NSString).pathExtension.lowercased()
        return ["mkv", "mp4", "m4v", "mov", "avi", "ts", "m2ts", "webm", "wmv", "flv", "mpg", "mpeg"].contains(ext)
            ? ext : "mkv"
    }
}

/// Byte, speed and time formatting for the Downloads rows.
enum DownloadFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(value, 0), countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Double) -> String? {
        guard bytesPerSecond > 1 else { return nil }
        return "\(bytes(Int64(bytesPerSecond)))/s"
    }

    static func eta(_ item: DownloadItem) -> String? {
        guard item.bytesPerSecond > 1, item.expectedBytes > item.bytesWritten else { return nil }
        let seconds = Double(item.expectedBytes - item.bytesWritten) / item.bytesPerSecond
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds).map { String(localized: "\($0) left") }
    }
}
#endif
