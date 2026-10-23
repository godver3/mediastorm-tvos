import AetherEngine
import Foundation

/// Whether live channels open with captions on: the last choice made in a live player's
/// Subtitles menu (any track on, or Off), kept across channels and launches.
enum LiveCaptionPreference {
    private static let key = "live.captionsOn"

    static var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The server's own closed captions for an HLS live session.
///
/// The engine finds CEA-608 itself when it demuxes the channel (a direct stream), but an
/// HLS session goes straight to AVPlayer, which only shows captions the playlist declares.
/// For those the server sniffs the session's segments for EIA-608 (`cc-status`) and, once
/// asked, extracts them to a growing SRT (`captions.srt`) on the session's own timeline,
/// as the Expo app plays them. This polls the status until detection finishes, then (while
/// selected) re-reads the SRT every few seconds and hands its cues on.
@MainActor
final class ServerLiveCaptions {
    private let sessionID: String
    private let log = AppLog(category: "live")
    private var statusTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

    /// The server found captions in this session's stream.
    private(set) var isAvailable = false
    var onAvailable: (() -> Void)?
    var onCues: (([SubtitleCue]) -> Void)?

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    /// Asks whether the session carries captions until the server has looked (it sniffs the
    /// first segments in the background, for up to about 25 seconds).
    func detect() {
        statusTask?.cancel()
        statusTask = Task { [weak self, sessionID] in
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                if let status = await APIClient.shared.liveCaptionStatus(sessionID), status.detectionDone {
                    guard let self, !Task.isCancelled else { return }
                    log.info("server captions for \(sessionID): \(status.hasClosedCaptions ? "found" : "none")")
                    if status.hasClosedCaptions {
                        isAvailable = true
                        onAvailable?()
                    }
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Starts re-reading the captions; the first request also starts the server's extractor.
    func start() {
        guard fetchTask == nil else { return }
        fetchTask = Task { [weak self, sessionID] in
            var lastSignature = ""
            while !Task.isCancelled {
                if let srt = await APIClient.shared.liveCaptionsSRT(sessionID), !Task.isCancelled {
                    let cues = SRTParser.cues(srt)
                    // The file only grows; republish when its tail changed.
                    let signature = cues.last.map { "\(cues.count)/\($0.id)/\($0.endTime)" } ?? "0"
                    if signature != lastSignature {
                        lastSignature = signature
                        self?.onCues?(cues)
                    }
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        onCues?([])
    }

    func cancel() {
        statusTask?.cancel()
        fetchTask?.cancel()
        statusTask = nil
        fetchTask = nil
    }
}

struct LiveCaptionStatus: Decodable {
    let hasClosedCaptions: Bool
    let detectionDone: Bool
}

extension APIClient {
    func liveCaptionStatus(_ sessionID: String) async -> LiveCaptionStatus? {
        try? await send("GET", "/api/video/hls/\(Self.segment(sessionID))/cc-status", promptOnLock: false, timeout: 10)
    }

    func liveCaptionsSRT(_ sessionID: String) async -> String? {
        guard let data = try? await sendRaw("GET", "/api/video/hls/\(Self.segment(sessionID))/captions.srt",
                                            promptOnLock: false, timeout: 10) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// SubRip to overlay cues.
enum SRTParser {
    static func cues(_ text: String) -> [SubtitleCue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]), let end = seconds(parts[1]), end > start else { continue }
            let body = lines[(timing + 1)...]
                .map(stripTags)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !body.isEmpty else { continue }
            // Stable across re-reads, and new when a roll-up caption's text changes.
            var hasher = Hasher()
            hasher.combine(Int(start * 1000))
            hasher.combine(body)
            cues.append(SubtitleCue(id: hasher.finalize(), startTime: start, endTime: end, body: .text(body)))
        }
        return cues.sorted { $0.startTime < $1.startTime }
    }

    /// "HH:MM:SS,mmm" (or with a dot), with anything after the time (cue settings) ignored.
    static func seconds(_ raw: String) -> Double? {
        let token = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        let fields = token.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard fields.count >= 2 else { return nil }
        var total = 0.0
        for field in fields {
            guard let value = Double(field) else { return nil }
            total = total * 60 + value
        }
        return total
    }

    /// Drops `<i>`-style markup and `{\an8}`-style overrides.
    private static func stripTags(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
    }
}
