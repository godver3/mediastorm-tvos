import AetherEngine
import Combine
import UIKit

/// Live timeshift: pause a channel, go back up to 30 minutes and return to live. For a direct
/// stream the engine keeps the window on the device (`dvrWindowSeconds`), bounded by its disk
/// budget (a quarter of the free space, at most 2 GiB), so a high-bitrate channel may hold less.
/// The server's timeshift setting is for Android TV only; an HLS session (the fallback) stays
/// live only.
///
/// On the native route AVKit's own transport bar does the rest: it shows the window as a
/// scrubber, pauses and seeks it, and offers its return-to-live. The software route has no AVKit
/// chrome, so Play/Pause, Left / Right (10 s) and Up (back to live) are handled here, with a
/// small status in the corner while the channel is paused or behind live.
extension LivePlayerViewController {
    /// How far back a direct tune can be paused or rewound.
    static var timeshiftWindowSeconds: Double { 30 * 60 }

    /// This tune keeps a timeshift window.
    var timeshifting: Bool { timeshiftWindow != nil }

    /// AVKit's linear-playback lock and the Play/Pause swallow follow the tune.
    func applyTimeshiftMode() {
        requiresLinearPlayback = !timeshifting
        playPauseSwallow?.isEnabled = !timeshifting
        if let window = timeshiftWindow { log.info("timeshift window \(Int(window / 60)) min") }
        updateTimeshiftStatus()
    }

    /// The software route's timeshift keys; true when the press was taken.
    func handleTimeshiftPress(_ presses: Set<UIPress>) -> Bool {
        guard timeshifting, softwareSurfaceMounted, let press = presses.first?.type else { return false }
        switch press {
        case .playPause:
            engine.togglePlayPause()
        case .leftArrow:
            skip(by: -Self.timeshiftSkipSeconds)
        case .rightArrow:
            skip(by: Self.timeshiftSkipSeconds)
        case .upArrow:
            Task { await engine.seekToLiveEdge() }
        default:
            return false
        }
        return true
    }

    private static var timeshiftSkipSeconds: Double { 10 }

    private func skip(by seconds: Double) {
        guard let range = engine.clock.seekableLiveRange else { return }
        let target = min(max(engine.clock.currentTime + seconds, range.lowerBound), range.upperBound)
        Task { await engine.seek(to: target) }
    }

    /// The software route's status, bound to the engine's live clock and state.
    func installTimeshiftStatus() {
        timeshiftStatus.isHidden = true
        timeshiftStatus.translatesAutoresizingMaskIntoConstraints = false
        overlayHost.addSubview(timeshiftStatus)
        NSLayoutConstraint.activate([
            timeshiftStatus.topAnchor.constraint(equalTo: overlayHost.topAnchor, constant: 60),
            timeshiftStatus.trailingAnchor.constraint(equalTo: overlayHost.trailingAnchor, constant: -80),
        ])
        engine.clock.$behindLiveSeconds
            .combineLatest(engine.$state)
            .throttle(for: .milliseconds(500), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.updateTimeshiftStatus() }
            .store(in: &cancellables)
    }

    func updateTimeshiftStatus() {
        let paused: Bool
        if case .paused = engine.state { paused = true } else { paused = false }
        let behind = engine.clock.behindLiveSeconds
        let shown = timeshifting && softwareSurfaceMounted && (paused || behind > LiveTimeshiftStatusView.atLiveSeconds)
        timeshiftStatus.isHidden = !shown
        if shown {
            timeshiftStatus.update(paused: paused, behindSeconds: behind)
            overlayHost.bringSubviewToFront(timeshiftStatus)
        }
    }
}

/// "Paused · 2:13 behind live · ↑ Live": the software route's stand-in for AVKit's live bar.
final class LiveTimeshiftStatusView: UIView {
    /// Within this of the edge the channel counts as live.
    static let atLiveSeconds: Double = 10

    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.1, alpha: 0.75)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 27, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(paused: Bool, behindSeconds: Double) {
        label.text = Self.text(paused: paused, behindSeconds: behindSeconds)
    }

    static func text(paused: Bool, behindSeconds: Double) -> String {
        var parts: [String] = []
        if paused { parts.append(String(localized: "Paused")) }
        if behindSeconds > atLiveSeconds {
            parts.append(String(localized: "\(clock(behindSeconds)) behind live"))
            parts.append(String(localized: "↑ Live"))
        }
        return parts.joined(separator: " · ")
    }

    /// "2:13", or "1:02:13" past an hour.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
