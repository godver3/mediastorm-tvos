#if os(tvOS)
import AVKit
import UIKit

/// The time of day in the top-right corner while AVKit's transport bar is up (shown on a
/// press, and kept up while paused), fading with it. The software route draws its own bar and
/// clock (`SoftwareTransportHUD`). Settings › Appearance › Show Clock turns both off.
extension EnginePlayerViewController: @preconcurrency AVPlayerViewControllerDelegate {
    func installClock() {
        delegate = self
        clockLabel.alpha = 0
        clockLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayHost.addSubview(clockLabel)
        NSLayoutConstraint.activate([
            clockLabel.topAnchor.constraint(equalTo: overlayHost.topAnchor, constant: PlayerClock.top),
            clockLabel.trailingAnchor.constraint(equalTo: overlayHost.trailingAnchor, constant: -PlayerClock.trailing),
        ])
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              willTransitionToVisibilityOfTransportBar visible: Bool,
                              with coordinator: AVPlayerViewControllerAnimationCoordinator) {
        let shown = visible && !softwareSurfaceMounted
        if shown {
            clockLabel.refresh()
            overlayHost.bringSubviewToFront(clockLabel)
        }
        coordinator.addCoordinatedAnimations({ self.clockLabel.alpha = shown ? 1 : 0 }, completion: nil)
    }
}
#endif
