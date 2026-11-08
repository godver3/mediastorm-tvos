#if os(iOS) && DEBUG
import ObjectiveC
import UIKit

/// Debug-only: the chrome probe (`-StrmrChromeProbe 1`, a stock AVPlayerViewController on Apple's
/// HLS sample) with the phone player's own controls over AVKit's, so the native route's menus,
/// skip button and visibility tracking can be checked on the simulator (where AetherEngine always
/// takes the software route). `-StrmrPlayAction 1` adds a Skip Intro button after 3 s.
extension ProbePlayerViewController {
    private enum Key { nonisolated(unsafe) static var tracker: UInt8 = 0 }

    func installMobileProbeControls(_ menus: [UIMenu]) {
        allowsPictureInPicturePlayback = true
        // `-StrmrProbeBare 1`: stock AVKit only, to tell AVKit's own behaviour from the overlay's.
        guard !UserDefaults.standard.bool(forKey: "StrmrProbeBare") else { return }
        speeds = []
        let controls = MobilePlayerControls(title: "Probe", subtitle: nil)
        EnginePlayerViewController.fill(controls, in: view)
        view.addSubview(controls)
        controls.setMenus(menus)
        let tracker = MobileChromeVisibility(root: view, controls: controls)
        tracker.start()
        objc_setAssociatedObject(self, &Key.tracker, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        guard UserDefaults.standard.bool(forKey: "StrmrPlayAction") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            controls.setAction(UIAction(title: String(localized: "Skip Intro")) { _ in })
        }
    }
}
#endif
