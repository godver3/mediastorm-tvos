import AetherEngine
import Foundation

/// Picking among online subtitle results, ported from the Expo app's
/// `utils/subtitle-helpers.ts` (`selectBestSubtitle`, `calculateReleaseSimilarity`,
/// `calculateEpisodeMatchScore`); keep the two in step.
enum OnlineSubtitleMatching {
    /// The result that best fits the playing release: the right episode first, then the
    /// closest release name, then the most downloads. With no release name, the right
    /// episode then the most downloads. nil for no results.
    static func selectBest(_ results: [SubtitleSearchResult], releaseName: String?,
                           season: Int?, episode: Int?) -> SubtitleSearchResult? {
        guard let first = results.first else { return nil }
        guard let releaseName, !releaseName.isEmpty else {
            return results.dropFirst().reduce(first) { best, current in
                let bestEpisode = episodeMatchScore(best.release, season: season, episode: episode)
                let currentEpisode = episodeMatchScore(current.release, season: season, episode: episode)
                if currentEpisode != bestEpisode { return currentEpisode > bestEpisode ? current : best }
                return current.downloads > best.downloads ? current : best
            }
        }
        let scored = results.enumerated().map { offset, result in
            (offset: offset, result: result,
             episode: episodeMatchScore(result.release, season: season, episode: episode),
             score: releaseSimilarity(releaseName, result.release))
        }
        // The offset keeps the sort stable, as JavaScript's is.
        let sorted = scored.sorted { a, b in
            if a.episode != b.episode { return a.episode > b.episode }
            if a.score != b.score { return a.score > b.score }
            if a.result.downloads != b.result.downloads { return a.result.downloads > b.result.downloads }
            return a.offset < b.offset
        }
        return sorted.first?.result
    }

    /// Results ordered for the search list: closest release first, then most downloads.
    static func sortedForList(_ results: [SubtitleSearchResult], releaseName: String?) -> [SubtitleSearchResult] {
        guard let releaseName, !releaseName.isEmpty else { return results }
        return results.enumerated()
            .map { (offset: $0.offset, result: $0.element, score: releaseSimilarity(releaseName, $0.element.release)) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.result.downloads != b.result.downloads { return a.result.downloads > b.result.downloads }
                return a.offset < b.offset
            }
            .map(\.result)
    }

    /// Share of the media release's tokens found in the subtitle's (0–100), plus 2 for each
    /// shared resolution / source / codec / audio / HDR token.
    static func releaseSimilarity(_ mediaRelease: String, _ subtitleRelease: String) -> Double {
        guard !mediaRelease.isEmpty, !subtitleRelease.isEmpty else { return 0 }
        let mediaTokens = Set(tokens(mediaRelease))
        let subTokens = Set(tokens(subtitleRelease))
        guard !mediaTokens.isEmpty, !subTokens.isEmpty else { return 0 }
        let shared = mediaTokens.filter(subTokens.contains)
        let bonus = shared.filter { token in importantPatterns.contains { matches($0, token) } }.count * 2
        return Double(shared.count) / Double(mediaTokens.count) * 100 + Double(bonus)
    }

    /// 1000 for the right SxxEyy / NxM, -1000 for another; 100 / -1000 for a season-only
    /// name; 500 / -500 for an episode-only one; 0 when the name says nothing (or this is
    /// not an episode).
    static func episodeMatchScore(_ release: String, season: Int?, episode: Int?) -> Int {
        guard let season, let episode, episode != 0 else { return 0 }
        for pattern in [#"\bS(\d{1,2})E(\d{1,3})\b"#, #"\b(\d{1,2})x(\d{1,3})\b"#] {
            guard let groups = firstMatch(pattern, in: release), groups.count == 2 else { continue }
            return Int(groups[0]) == season && Int(groups[1]) == episode ? 1000 : -1000
        }
        for pattern in [#"\bS(\d{1,2})\b"#, #"\bseason\s*\.?\s*(\d{1,2})\b"#] {
            guard let groups = firstMatch(pattern, in: release), let found = groups.first else { continue }
            return Int(found) == season ? 100 : -1000
        }
        for pattern in [#"\b(?:episode|ep)\s*\.?\s*(\d{1,3})\b"#, #"\bE(\d{2,3})\b"#] {
            guard let groups = firstMatch(pattern, in: release), let found = groups.first else { continue }
            return Int(found) == episode ? 500 : -500
        }
        return 0
    }

    // MARK: Helpers

    private static let importantPatterns = [
        #"^\d{3,4}p$"#,
        #"^(bluray|bdrip|brrip|webrip|web-dl|webdl|hdtv|hdrip|dvdrip)$"#,
        #"^(x264|x265|h264|h265|hevc|avc|xvid)$"#,
        #"^(dts|ac3|aac|truehd|atmos|dd5|ddp5|eac3)$"#,
        #"^(hdr|hdr10|dv|dolby|vision)$"#,
    ]

    /// Lowercased, extension dropped, split on `.`, `_`, `-` and whitespace, one-letter tokens dropped.
    private static func tokens(_ value: String) -> [String] {
        value.lowercased()
            .replacingOccurrences(of: #"\.(mkv|mp4|avi|srt|sub)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "[._-]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.utf16.count > 1 }
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The capture groups of the first case-insensitive match.
    private static func firstMatch(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: value).map { String(value[$0]) } ?? ""
        }
    }
}

/// WebVTT from the server's subtitle endpoints (download, extraction, translation).
enum WebVTT {
    /// Cue timing lines, as the Expo player's `countVttCues` counts them: `HH:MM:SS.mmm`
    /// pairs, else `MM:SS.mmm` pairs.
    static func cueCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let full = count(#"\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}"#, in: text)
        return full > 0 ? full : count(#"\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}\.\d{3}"#, in: text)
    }

    /// Overlay cues. The SubRip parser already reads WebVTT timing (dot or comma, with or
    /// without hours, cue settings ignored) and skips the header and NOTE / STYLE blocks;
    /// the common character references are decoded first.
    static func cues(_ text: String) -> [SubtitleCue] {
        var decoded = text
        for (entity, value) in [("&nbsp;", " "), ("&lrm;", ""), ("&rlm;", ""), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }
        return SRTParser.cues(decoded)
    }

    private static func count(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
