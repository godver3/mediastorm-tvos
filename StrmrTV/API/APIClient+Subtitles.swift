import Foundation

/// Online subtitles: provider search and download, embedded-track extraction, and the
/// server's incremental translation, as the Expo player uses them. All are fetched here
/// with the app's own headers, so no `token=` rides in a URL.
extension APIClient {
    /// What `/api/settings` says about online subtitles.
    struct SubtitleServerSettings {
        /// OpenSubtitles (username and password), SubDL or SubSource is set up. The server
        /// masks the values but leaves them non-empty.
        var providerConfigured = false
        /// `subtitles.enableTranslatedSubs` (on unless turned off).
        var translationEnabled = true
    }

    /// What is being played, for the subtitle search and download.
    struct SubtitleQuery {
        var imdbID: String?
        var title: String?
        var year: Int?
        var season: Int?
        var episode: Int?
        var releaseName: String?

        var items: [String: String] {
            var q: [String: String] = [:]
            if let imdbID, !imdbID.isEmpty { q["imdbId"] = imdbID }
            if let title, !title.isEmpty { q["title"] = title }
            if let year { q["year"] = String(year) }
            if let season { q["season"] = String(season) }
            if let episode { q["episode"] = String(episode) }
            return q
        }
    }

    func subtitleServerSettings() async -> SubtitleServerSettings? {
        struct Subtitles: Decodable {
            let openSubtitlesUsername: String?
            let openSubtitlesPassword: String?
            let subdlApiKey: String?
            let subsourceApiKey: String?
            let enableTranslatedSubs: Bool?
        }
        struct Settings: Decodable { let subtitles: Subtitles? }
        guard let settings: Settings = try? await send("GET", "/api/settings", promptOnLock: false, timeout: 10) else {
            return nil
        }
        let s = settings.subtitles
        func set(_ value: String?) -> Bool { !(value ?? "").isEmpty }
        return SubtitleServerSettings(
            providerConfigured: (set(s?.openSubtitlesUsername) && set(s?.openSubtitlesPassword))
                || set(s?.subdlApiKey) || set(s?.subsourceApiKey),
            translationEnabled: s?.enableTranslatedSubs ?? true)
    }

    /// The profile's `playback.allowedTrackLanguages` (empty = all).
    func allowedTrackLanguages() async -> [String] {
        struct Playback: Decodable { let allowedTrackLanguages: [String]? }
        struct UserSettings: Decodable { let playback: Playback? }
        let user: UserSettings? = try? await send("GET", "\(profilePath)/settings", promptOnLock: false, timeout: 10)
        return user?.playback?.allowedTrackLanguages ?? []
    }

    func searchSubtitles(_ query: SubtitleQuery, language: String) async throws -> [SubtitleSearchResult] {
        var q = query.items
        if let release = query.releaseName, !release.isEmpty { q["releaseName"] = release }
        q["language"] = language
        // The providers are slow; the Expo app waits as long as its default request timeout.
        return try await send("GET", "/api/subtitles/search", query: q, promptOnLock: false, timeout: 60)
    }

    /// The result as WebVTT.
    func downloadSubtitle(_ result: SubtitleSearchResult, query: SubtitleQuery, language: String) async throws -> String {
        var q = query.items
        q["subtitleId"] = result.id
        q["provider"] = result.provider
        q["language"] = language
        let data = try await sendRaw("GET", "/api/subtitles/download", query: q, promptOnLock: false, timeout: 60)
        return String(decoding: data, as: UTF8.self)
    }

    /// Starts extracting the source's `subtitleTrack`-th subtitle stream to WebVTT from
    /// `startOffset` (timestamps are kept, so cues stay on the media's timeline).
    func startSubtitleExtract(path: String, subtitleTrack: Int, startOffset: Double?) async throws -> SubtitleExtractStart {
        var q = ["path": path, "subtitleTrack": String(subtitleTrack), "format": "vtt"]
        if let startOffset, startOffset > 0 { q["startOffset"] = String(format: "%.3f", startOffset) }
        return try await send("GET", "/api/video/subtitles/start", query: q, promptOnLock: false, timeout: 30)
    }

    /// One translation pass over `sourcePath` (server-relative, so the server reads it over its
    /// own loopback with this request's Authorization). Each call translates a few more cues
    /// and returns everything done so far.
    func translateSubtitles(sourcePath: String, from sourceLanguage: String, to targetLanguage: String) async throws -> String {
        let q = ["sourceUrl": sourcePath, "targetLanguage": targetLanguage, "sourceLanguage": sourceLanguage,
                 "userId": profileID]
        let data = try await sendRaw("GET", "/api/subtitles/translate", query: q, promptOnLock: false, timeout: 45)
        return String(decoding: data, as: UTF8.self)
    }
}
