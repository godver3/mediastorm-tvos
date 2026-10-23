import AetherEngine
import UIKit

/// Intro / recap / credits ranges for the playing item from `POST /api/video/segments`,
/// which merges IntroDB, SkipDB and chapter names server-side. Re-posted whenever the
/// duration or the container chapters change.
@MainActor
final class SkipSegments {
    private let request: PlaybackRequest
    private var segments: [SkipSegment] = []
    private var postedKey: String?
    private var task: Task<Void, Never>?

    init(request: PlaybackRequest) {
        self.request = request
    }

    func refresh(duration: Double, chapters: [ChapterInfo]) {
        let key = "\(Int(duration))|\(chapters.count)"
        guard duration > 0, key != postedKey else { return }
        postedKey = key

        var body: [String: Any] = [
            "duration": duration,
            "chapters": chapters.map { chapter -> [String: Any] in
                var c: [String: Any] = ["title": chapter.name, "start": chapter.startSeconds]
                if chapter.durationSeconds > 0 { c["end"] = chapter.startSeconds + chapter.durationSeconds }
                return c
            },
        ]
        if let imdb = request.title.imdbID { body["imdbId"] = imdb }
        if let ep = request.episode {
            body["season"] = ep.season
            body["episode"] = ep.episode
        }
        task?.cancel()
        task = Task { [weak self] in
            guard let found = try? await APIClient.shared.skipSegments(body), !Task.isCancelled else { return }
            self?.segments = found
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// The segment playback is inside, when it merits a button. Movie end credits are left
    /// alone (skipping them only ends the film, and may skip a post-credits scene).
    func active(at time: Double) -> SkipSegment? {
        segments.first { segment in
            time >= segment.start && time < segment.end - 1 && (segment.type != "outro" || request.isEpisode)
        }
    }

    /// The transport bar's contextual button for `segment`: Next Episode at the credits when
    /// there is an aired next episode (with the seconds left when it will play by itself),
    /// otherwise a seek past the segment.
    static func action(for segment: SkipSegment, next: PlaybackRequest?, countdown: Int? = nil,
                       skip: @escaping @MainActor (Double) -> Void,
                       playNext: @escaping @MainActor (PlaybackRequest) -> Void) -> UIAction {
        if segment.type == "outro", let next {
            let title = countdown.map { String(localized: "Next Episode in \($0)") } ?? String(localized: "Next Episode")
            return UIAction(title: title, image: UIImage(systemName: "forward.end.fill")) { _ in playNext(next) }
        }
        let title = switch segment.type {
        case "intro": "Skip Intro"
        case "recap": "Skip Recap"
        case "outro": "Skip Credits"
        default: "Skip Preview"
        }
        return UIAction(title: title) { _ in skip(segment.end) }
    }
}
