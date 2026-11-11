import AetherEngine
import UIKit

/// On-device credits detection: with Settings › Playback › Credits Detection on and no credits
/// range from the server, frames past 90 % of an episode are read for credit text, and once found
/// the credits become an outro segment, so Next Episode (and its auto-skip countdown) shows as it
/// does for a server range. Frames come only from what the engine already holds
/// (`scrubPreviewFrame`): a frame that isn't resident is skipped, never fetched.
extension PlayerViewController {
    /// The still's long edge; enough for credit text, small enough to recognise quickly.
    private static let creditsFrameWidth = 960

    func sampleCreditsIfDue(at time: Double) {
        guard creditsDetectionEnabled, request.isEpisode, nextEpisode != nil, !engine.isLive,
              !skipSegments.hasOutro, !isAdvancing, !didFinish else { return }
        let duration = engine.duration
        let refined = creditsDetection.isFine
        guard creditsDetection.shouldSample(at: time, duration: duration) else { return }
        creditsTask = Task { [weak self] in
            guard let self else { return }
            let frame = await engine.scrubPreviewFrame(atSeconds: time, refined: refined,
                                                       maxWidth: Self.creditsFrameWidth, isCancelled: { false })
            guard let frame, !Task.isCancelled else {
                creditsDetection.skip()
                return
            }
            let image = frame.image
            let lines = await Task.detached(priority: .utility) { CreditsOCR.lines(in: image) }.value
            guard !Task.isCancelled else {
                creditsDetection.skip()
                return
            }
            guard let start = creditsDetection.record(lines, at: frame.actualSeconds) else { return }
            log.notice("credits detected on device at \(Int(start))s")
            skipSegments.addDetectedCredits(start: start, end: duration)
            updateSkipAction(at: engine.clock.currentTime)
        }
    }

    func cancelCreditsDetection() {
        creditsTask?.cancel()
        creditsTask = nil
    }
}
