#if os(iOS)
import UIKit

/// Follows AVKit's iOS playback chrome so the player's own controls (`MobilePlayerControls`) come
/// and go with it, and lines the menu row up with AVKit's top bar.
///
/// AVPlayerViewController has no public signal for its controls showing or hiding on iOS, so its
/// play / pause group is found in the view tree and its visibility read once per frame while the
/// player is up (one pointer walk up a dozen views; the tree search runs only until it is found).
/// The group is matched by class-name suffix, which holds across AVKit's iOS 18
/// (`AVMobileChromeless…`) and iOS 26+ (`AVMobileGlass…`) chrome. When it cannot be found (a
/// future AVKit), the controls fall back to showing with any tap and hiding a few seconds later,
/// as AVKit's own do.
@MainActor
final class MobileChromeVisibility {
    private weak var root: UIView?
    private weak var controls: MobilePlayerControls?
    private weak var playbackGroup: UIView?
    private weak var volumeGroup: UIView?
    private var link: CADisplayLink?
    private var lastSearch: CFTimeInterval = 0
    private var lastVisible: Bool?
    private var fallbackTap: UITapGestureRecognizer?
    private var fallbackHide: DispatchWorkItem?

    init(root: UIView, controls: MobilePlayerControls) {
        self.root = root
        self.controls = controls
    }

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.tick() }, selector: #selector(DisplayLinkTarget.fire))
        // A tenth of a second is quick enough to fade in with AVKit's own fade.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 10)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        if let fallbackTap { fallbackTap.view?.removeGestureRecognizer(fallbackTap) }
        fallbackTap = nil
    }

    private func tick() {
        guard let root, root.window != nil, let controls, !controls.ownsTransport else {
            lastVisible = nil
            return
        }
        if playbackGroup?.window == nil { findGroups(in: root) }
        guard let playbackGroup else { return installFallback() }
        let visible = Self.isVisible(playbackGroup, below: root)
        alignRow()
        guard visible != lastVisible else { return }
        lastVisible = visible
        controls.setChrome(visible: visible)
    }

    private func findGroups(in root: UIView) {
        let now = CACurrentMediaTime()
        guard now - lastSearch > 0.5 else { return }
        lastSearch = now
        playbackGroup = Self.find(in: root) { Self.className($0).hasSuffix("PlaybackControlsView") }
        volumeGroup = Self.find(in: root) { Self.className($0).hasSuffix("VolumeControlsView") }
    }

    /// The menu row sits in AVKit's top bar, just before its volume group.
    private func alignRow() {
        guard let controls, let volumeGroup, volumeGroup.window != nil, volumeGroup.bounds.width > 0 else { return }
        let frame = volumeGroup.convert(volumeGroup.bounds, to: controls)
        let safe = controls.bounds.inset(by: controls.safeAreaInsets)
        controls.setOverlayTop(max(0, frame.midY - 22 - safe.minY), trailing: max(0, safe.maxX - frame.minX + 12))
    }

    /// Whether `view` and every ancestor up to `root` is shown.
    private static func isVisible(_ view: UIView, below root: UIView) -> Bool {
        var current: UIView? = view
        while let v = current, v !== root {
            if v.isHidden || v.alpha < 0.05 { return false }
            current = v.superview
        }
        return current === root
    }

    private static func className(_ view: UIView) -> String { String(describing: type(of: view)) }

    private static func find(in view: UIView, where match: (UIView) -> Bool) -> UIView? {
        if match(view) { return view }
        for sub in view.subviews {
            if let found = find(in: sub, where: match) { return found }
        }
        return nil
    }

    // MARK: Fallback

    private func installFallback() {
        guard fallbackTap == nil, let root else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(fallbackTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = SimultaneousDelegate.shared
        root.addGestureRecognizer(tap)
        fallbackTap = tap
    }

    @objc private func fallbackTapped() {
        guard let controls, playbackGroup == nil else { return }
        controls.setChrome(visible: !controls.isChromeVisible)
        fallbackHide?.cancel()
        let work = DispatchWorkItem { [weak controls] in controls?.setChrome(visible: false) }
        fallbackHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}

/// CADisplayLink retains its target; this breaks the cycle.
@MainActor
private final class DisplayLinkTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

@MainActor
private final class SimultaneousDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SimultaneousDelegate()
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif
