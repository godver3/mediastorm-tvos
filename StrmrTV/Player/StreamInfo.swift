import AetherEngine
import Foundation

/// The player's Stream tab (`StreamInfoViewController`): what is playing and from where, as
/// label / value rows. The file and source are known when playback starts; the video and audio
/// lines are read from the engine as it learns them. Labels follow the Expo player's header
/// (`TVPlaybackHeader`, `utils/debrid-provider.ts`).
struct StreamInfo: Equatable {
    struct Row: Equatable {
        let label: String
        let value: String
    }

    var file: String?
    var source: String?
    var video: String?
    var dynamicRange: String?
    var audio: String?
    /// One line for the software route's HUD, which has no Info tabs: "4K HEVC · HDR10 · E-AC-3 5.1 · Usenet".
    var summary: String?

    var rows: [Row] {
        [
            (String(localized: "File"), file),
            (String(localized: "Video"), video),
            (String(localized: "Dynamic Range"), dynamicRange),
            (String(localized: "Audio"), audio),
            (String(localized: "Source"), source),
        ].compactMap { label, value in
            guard let value, !value.isEmpty else { return nil }
            return Row(label: label, value: value)
        }
    }
}

// MARK: - Source

/// Where a stream comes from: "Debrid · Real-Debrid", "Usenet · NZBGeek", "Plex · Films".
enum StreamSource {
    /// From the server's service type and provider when it named them, else from the stream path
    /// (`localmedia:` / `plexmedia:` / `jellyfinmedia:` / `…/debrid/<provider>/…`; anything else
    /// is usenet), as the Expo player infers it.
    static func label(path: String?, serviceType: String? = nil, debridProvider: String? = nil,
                      indexer: String? = nil) -> String? {
        let rawPath = (path ?? "").trimmingCharacters(in: .whitespaces)
        let path = rawPath.lowercased()
        let service = (serviceType ?? "").lowercased()
        if path.hasPrefix("localmedia:") { return LibrarySource.local.label }
        if path.hasPrefix("plexmedia:") { return LibrarySource.plex.label }
        if path.hasPrefix("jellyfinmedia:") { return LibrarySource.jellyfin.label }
        if service == "debrid" || (service.isEmpty && path.contains("/debrid/")) {
            let provider = providerName(nonEmpty(debridProvider) ?? Self.debridProvider(fromPath: rawPath))
            return joined([String(localized: "Debrid"), provider])
        }
        if service == "usenet" || !path.isEmpty {
            return joined([String(localized: "Usenet"), nonEmpty(indexer)])
        }
        return nil
    }

    /// `sourceServiceType` / `debridProvider` for `/api/video/stream`: the dashboard otherwise
    /// guesses from the path and calls anything outside `/debrid/` (a direct debrid link, a
    /// library file) usenet. Library paths win; then the server's service type; then the path.
    static func trackerQuery(path: String?, serviceType: String?, debridProvider: String?) -> [String: String] {
        let rawPath = (path ?? "").trimmingCharacters(in: .whitespaces)
        let path = rawPath.lowercased()
        let service: String? = if path.hasPrefix("localmedia:") { "local" }
            else if path.hasPrefix("plexmedia:") { "plex" }
            else if path.hasPrefix("jellyfinmedia:") { "jellyfin" }
            else { nonEmpty(serviceType?.lowercased()) ?? (path.contains("/debrid/") ? "debrid" : nil) }
        var query: [String: String] = [:]
        if let service { query["sourceServiceType"] = service }
        if service == "debrid", let provider = nonEmpty(debridProvider) ?? Self.debridProvider(fromPath: rawPath) {
            query["debridProvider"] = provider
        }
        return query
    }

    /// The debrid provider's display name ("realdebrid" / "Real Debrid" → "Real-Debrid").
    static func providerName(_ raw: String?) -> String? {
        guard let raw = nonEmpty(raw) else { return nil }
        let key = raw.lowercased().filter { $0.isLetter || $0.isNumber }
        return providerNames[key] ?? raw
    }

    /// The provider segment of a `/debrid/<provider>/…` stream path.
    static func debridProvider(fromPath path: String) -> String? {
        guard let range = path.range(of: "/debrid/", options: .caseInsensitive) else { return nil }
        let segment = path[range.upperBound...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        return nonEmpty(String(segment).removingPercentEncoding ?? String(segment))
    }

    private static let providerNames = [
        "alldebrid": "AllDebrid",
        "debridlink": "Debrid-Link",
        "premiumize": "Premiumize",
        "realdebrid": "Real-Debrid",
        "torbox": "TorBox",
    ]

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }

    static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Video and audio

enum StreamFormat {
    /// "3840×2160 (4K) · HEVC Main 10 · 23.976 fps · 18.4 Mbps".
    static func video(width: Int, height: Int, codec: String?, profile: String?, frameRate: Double?,
                      bitrate: Int64) -> String? {
        var parts: [String?] = []
        if width > 0, height > 0 { parts.append("\(width)×\(height) (\(resolutionName(height: height)))") }
        if let codec = videoCodecName(codec) {
            parts.append(StreamSource.joined([codec, profile]).replacingOccurrences(of: " · ", with: " "))
        }
        if let frameRate, frameRate > 0 { parts.append("\(trimmed(frameRate, digits: 3)) fps") }
        parts.append(self.bitrate(bitrate))
        let line = StreamSource.joined(parts)
        return line.isEmpty ? nil : line
    }

    /// "4K HEVC" for the HUD's summary.
    static func compactVideo(height: Int, codec: String?) -> String? {
        let line = [height > 0 ? resolutionName(height: height) : nil, videoCodecName(codec)]
            .compactMap { $0 }.joined(separator: " ")
        return line.isEmpty ? nil : line
    }

    /// "E-AC-3 5.1 Atmos" for the HUD's summary.
    static func compactAudio(_ track: TrackInfo?) -> String? {
        guard let track else { return nil }
        let codec = TrackLabels.format(track.codec)
        let line = [codec.isEmpty ? nil : codec, channels(track.channels), track.isAtmos ? "Atmos" : nil,
                    track.isDTSX ? "DTS:X" : nil].compactMap { $0 }.joined(separator: " ")
        return line.isEmpty ? nil : line
    }

    /// Height buckets as the Expo header reads them, with UHD named 4K.
    static func resolutionName(height: Int) -> String {
        if height > 1080 { return "4K" }
        if height > 720 { return "1080p" }
        if height == 720 { return "720p" }
        return "SD"
    }

    static func videoCodecName(_ codec: String?) -> String? {
        switch (codec ?? "").lowercased() {
        case "": nil
        case "hevc", "h265": "HEVC"
        case "h264", "avc": "H.264"
        case "av1": "AV1"
        case "vp9": "VP9"
        case "mpeg2video": "MPEG-2"
        case "vc1": "VC-1"
        case let other: other.uppercased()
        }
    }

    /// "Dolby Vision Profile 8", "HDR10", or "SDR": what the file carries. The engine's on-screen
    /// format (`videoFormat`) is not shown; it reads the panel's mode from the screen's headroom,
    /// which misses a TV that is presenting HDR and labelled DV sessions "Shown as SDR".
    static func formatName(_ format: VideoFormat, dvProfile: Int?) -> String {
        switch format {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .hlg: "HLG"
        case .dolbyVision: dvProfile.map { String(localized: "Dolby Vision Profile \($0)") } ?? "Dolby Vision"
        }
    }

    /// "E-AC-3 · 5.1 · Atmos · English · 768 kbps · 48 kHz".
    static func audio(_ track: TrackInfo?) -> String? {
        guard let track else { return nil }
        let codec = TrackLabels.format(track.codec)
        var parts: [String?] = [codec.isEmpty ? nil : codec]
        // libavcodec's profile carries the useful variants ("DTS-HD MA", "Dolby TrueHD + Dolby Atmos").
        if let profile = track.profile, !profile.isEmpty, profile.lowercased() != track.codec.lowercased(),
           !["lc", "main"].contains(profile.lowercased()) {
            parts.append(profile)
        }
        parts.append(channels(track.channels))
        let profileText = (track.profile ?? "").lowercased()
        if track.isAtmos, !profileText.contains("atmos") { parts.append("Atmos") }
        if track.isDTSX, !profileText.contains("dts:x") { parts.append("DTS:X") }
        if let language = track.language, !language.isEmpty, language.lowercased() != "und" {
            parts.append(TrackLabels.language(language))
        }
        parts.append(bitrate(track.bitrate))
        if track.sampleRate > 0 { parts.append("\(trimmed(Double(track.sampleRate) / 1000, digits: 1)) kHz") }
        let line = StreamSource.joined(parts)
        return line.isEmpty ? nil : line
    }

    static func channels(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: String(localized: "Mono")
        case 2: String(localized: "Stereo")
        case 6: "5.1"
        case 8: "7.1"
        default: String(localized: "\(count) ch")
        }
    }

    /// "18.4 Mbps" / "640 kbps"; nil when the container declares none.
    static func bitrate(_ bitsPerSecond: Int64) -> String? {
        guard bitsPerSecond > 0 else { return nil }
        let mbps = Double(bitsPerSecond) / 1_000_000
        if mbps >= 1 { return "\(String(format: "%.1f", mbps)) Mbps" }
        return "\(Int((Double(bitsPerSecond) / 1000).rounded())) kbps"
    }

    /// A number with at most `digits` decimals and no trailing zeros (23.976, 24, 44.1).
    private static func trimmed(_ value: Double, digits: Int) -> String {
        var text = String(format: "%.\(digits)f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
