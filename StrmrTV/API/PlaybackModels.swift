import Foundation

// MARK: - Manual source selection

/// One indexer/scraper result. The raw JSON is kept verbatim because the backend's
/// resolve endpoint takes the result back exactly as it was returned.
struct SourceResult: Identifiable, @unchecked Sendable {
    let raw: [String: Any]
    /// Position in the server's response; source-health updates are keyed by it.
    let index: Int
    let id: String
    let title: String
    let indexer: String
    let sizeBytes: Int64
    let serviceType: String
    let attributes: [String: String]
    /// Debrid cache / usenet health annotation (`includeSourceHealth=true`).
    let health: SourceHealth?

    init?(_ raw: [String: Any], index: Int) {
        guard let title = raw["title"] as? String else { return nil }
        self.raw = raw
        self.index = index
        health = (raw["sourceHealth"] as? [String: Any]).flatMap(SourceHealth.init)
        self.title = title
        id = (raw["guid"] as? String) ?? title
        indexer = (raw["indexer"] as? String) ?? ""
        sizeBytes = (raw["sizeBytes"] as? NSNumber)?.int64Value ?? 0
        serviceType = (raw["serviceType"] as? String) ?? ""
        attributes = ((raw["attributes"] as? [String: Any]) ?? [:]).compactMapValues { value in
            switch value {
            case let s as String: s
            case let n as NSNumber: n.stringValue
            default: nil
            }
        }
    }
}

extension SourceResult {
    var debridProvider: String? { attributes["debridProvider"] ?? attributes["provider"] }

    /// "Debrid · Real-Debrid" / "Usenet · NZBGeek" for the stream this result resolved to.
    func sourceLabel(path: String) -> String? {
        StreamSource.label(path: path, serviceType: serviceType, debridProvider: debridProvider, indexer: indexer)
    }
}

struct SourceHealth: Decodable, Hashable {
    /// healthy | cached | unhealthy | not_cached | pending | unknown
    let state: String
    /// Poll token while `state` is pending.
    let token: String?

    init(state: String, token: String?) {
        self.state = state
        self.token = token
    }

    init?(_ raw: [String: Any]) {
        guard let state = raw["state"] as? String else { return nil }
        self.init(state: state, token: raw["token"] as? String)
    }
}

/// `GET /api/indexers/source-health` long-poll response.
struct SourceHealthSnapshot: Decodable {
    struct Entry: Decodable {
        let index: Int
        let health: SourceHealth
    }
    let complete: Bool
    let results: [Entry]
}

struct PlaybackResolution: Decodable {
    let queueId: Int64?
    let webdavPath: String?
    let trackSelection: TrackSelection?
}

// MARK: - Tracks

/// One container track the server chose (`streamIndex` is the container number,
/// `typeIndex` the position among same-kind tracks).
struct SelectedTrack: Decodable, Hashable {
    let streamIndex: Int
    let typeIndex: Int
    let language: String?
    let languageCode: String?
    let languageIndex: Int
    let languageCount: Int
    let codec: String?
    let title: String?
    let forced: Bool?
    let bitmap: Bool?
}

/// The server's audio / subtitle choice for a source, from the profile's preferences.
struct TrackSelection: Decodable, Hashable {
    let audio: SelectedTrack?
    let subtitle: SelectedTrack?
    /// `subtitle` restricted to text codecs (equal to it when it is already text).
    let textSubtitle: SelectedTrack?
    let audioLanguage: String?
    let subtitleLanguage: String?
    /// off | forced-only | on
    let subtitleMode: String?
}

// MARK: - Skip segments

struct SkipSegment: Decodable, Hashable {
    /// intro | recap | outro | preview
    let type: String
    let start: Double
    let end: Double
}

struct SkipSegmentsResponse: Decodable {
    let segments: [SkipSegment]?
}

// MARK: - Prequeue

struct PrequeueStartResponse: Decodable {
    let prequeueId: String
    let status: String
}

struct PrequeueTrack: Decodable {
    let index: Int
    let absoluteIndex: Int?
    let language: String?
    let title: String?
    let codec: String?
    let forced: Bool?
    let isBitmap: Bool?
}

/// A source audio stream (`index` is the container stream number).
struct PrequeueAudioTrack: Decodable {
    let index: Int
    let language: String?
    let codec: String?
    /// The codec profile ("E-AC-3 + Atmos"), from newer servers.
    let profile: String?
    let title: String?
}

struct PrequeueStatus: Decodable {
    struct TargetEpisode: Decodable {
        let seasonNumber: Int
        let episodeNumber: Int
    }

    let prequeueId: String
    let status: String
    /// The episode being resolved; the server picks the next-up one when none was asked for.
    let targetEpisode: TargetEpisode?
    /// ffprobe stream index of the profile's preferred audio track; -1 = default.
    let selectedAudioTrack: Int?
    /// 0-based index into `subtitleTracks`; -1 = off.
    let selectedSubtitleTrack: Int?
    let subtitleTracks: [PrequeueTrack]?
    let audioTracks: [PrequeueAudioTrack]?
    /// Explicit track choice (newer servers); preferred over the two fields above.
    let trackSelection: TrackSelection?
    let progressStage: String?
    let progressDetail: String?
    let streamPath: String?
    let displayName: String?
    let duration: Double?
    let error: String?
    /// The release picked (AIOStreams passthrough name, the indexer result, its attributes).
    let passthroughName: String?
    let selectedResult: SelectedResult?
    let resultAttributes: [String: String]?
    /// "usenet" / "debrid", and the debrid service that resolved it, for the player's Stream tab.
    let serviceType: String?
    let debridProvider: String?

    struct SelectedResult: Decodable {
        let title: String?
        let attributes: [String: String]?
        let indexer: String?
        let serviceType: String?
    }

    var resolvedServiceType: String? { serviceType ?? selectedResult?.serviceType }
    var resolvedDebridProvider: String? {
        let attrs = resultAttributes ?? selectedResult?.attributes ?? [:]
        return debridProvider ?? attrs["debridProvider"] ?? attrs["provider"]
    }

    /// "Debrid · Real-Debrid" / "Usenet · NZBGeek".
    var sourceLabel: String? {
        StreamSource.label(path: streamPath, serviceType: resolvedServiceType,
                           debridProvider: resolvedDebridProvider, indexer: selectedResult?.indexer)
    }
}

// MARK: - Online subtitles

/// One `GET /api/subtitles/search` result.
struct SubtitleSearchResult: Decodable, Hashable, Identifiable {
    let id: String
    let provider: String
    let language: String
    let release: String
    let downloads: Int
    let hearingImpaired: Bool

    private enum CodingKeys: String, CodingKey {
        case id, provider, language, release, downloads
        case hearingImpaired = "hearing_impaired"
    }

    init(id: String, provider: String, language: String = "", release: String, downloads: Int = 0,
         hearingImpaired: Bool = false) {
        self.id = id
        self.provider = provider
        self.language = language
        self.release = release
        self.downloads = downloads
        self.hearingImpaired = hearingImpaired
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Providers send numeric ids too.
        if let text = try? c.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = String(try c.decode(Int64.self, forKey: .id))
        }
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? ""
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? ""
        release = try c.decodeIfPresent(String.self, forKey: .release) ?? ""
        downloads = (try? c.decodeIfPresent(Int.self, forKey: .downloads)) ?? 0
        hearingImpaired = (try? c.decodeIfPresent(Bool.self, forKey: .hearingImpaired)) ?? false
    }
}

/// `GET /api/video/subtitles/start`: an embedded track being extracted to WebVTT.
struct SubtitleExtractStart: Decodable {
    let sessionId: String
    /// Server-relative (`/api/video/subtitles/{id}/subtitles.vtt`).
    let subtitleUrl: String
}

/// The server's answer to a progress report: whether it wants the player off this source.
struct ProgressReply: Decodable {
    var migrationRequested: Bool?
    var migrationReason: String?
}
