#if os(iOS)
import UIKit

private let log = AppLog(category: "chrome")

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
    private var lastVolumeExpanded = false
    private var fallbackTap: UITapGestureRecognizer?
    private var fallbackHide: DispatchWorkItem?
    /// When the tracker started; the fallback waits for AVKit to build its chrome first.
    private var startedAt: CFTimeInterval = 0
    /// False where the controls are only an addition to AVKit's chrome and can go without it
    /// (live): no tap recognizer then ever goes on the player's view.
    var allowsFallback = true
    /// How long AVKit's chrome may take to appear before the fallback tap goes in.
    private static let fallbackDelay: CFTimeInterval = 2

    init(root: UIView, controls: MobilePlayerControls) {
        self.root = root
        self.controls = controls
    }

    func start() {
        guard link == nil else { return }
        startedAt = CACurrentMediaTime()
        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] in self?.tick() }, selector: #selector(DisplayLinkTarget.fire))
        // AVKit's chrome fades in 0.15 s; checking 30 times a second finds its animation while it
        // still runs, so the controls can copy it (`MobilePlayerControls.setChrome`).
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
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
        guard let playbackGroup else {
            if CACurrentMediaTime() - startedAt > Self.fallbackDelay { installFallback() }
            return
        }
        // A tap recognizer on the player's view makes AVKit's own tap-to-show fail, so the
        // fallback must never outlive AVKit's chrome turning up.
        removeFallback()
        let visible = Self.isVisible(playbackGroup, below: root)
        // The volume slider opens leftwards over the menu row: the row fades out meanwhile, and
        // stays where it was rather than following the group.
        let expanded = volumeExpanded
        if expanded != lastVolumeExpanded {
            lastVolumeExpanded = expanded
            log.info("volume slider \(expanded ? "open" : "closed"): \(volumeLayout)")
            controls.setMenuRowCovered(expanded)
        }
        if !expanded { alignRow() }
        guard visible != lastVisible else { return }
        lastVisible = visible
        log.info("chrome \(visible ? "shown" : "hidden")")
        controls.setChrome(visible: visible, following: volumeGroup?.layer)
    }

    /// AVKit's volume group is wider while its slider is open. Its closed width differs between
    /// releases (44 pt round on iOS 27.2, 202 pt on 27.3), so the narrowest width seen counts as
    /// closed and the slider as open only well past it.
    private var volumeExpanded: Bool {
        guard let volumeGroup, volumeGroup.window != nil, volumeGroup.bounds.width > 0 else { return false }
        let widest = volumeGroup.subviews.lazy.filter { !$0.isHidden && $0.alpha > 0.05 }
            .reduce(volumeGroup.bounds.width) { max($0, $1.frame.width) }
        volumeRestWidth = min(volumeRestWidth ?? widest, widest)
        return widest > (volumeRestWidth ?? widest) + 24
    }
    private var volumeRestWidth: CGFloat?

    private var volumeLayout: String {
        guard let volumeGroup else { return "-" }
        let parts = volumeGroup.subviews.map { "\(Self.className($0)) w=\(Int($0.frame.width)) a=\($0.alpha) h=\($0.isHidden)" }
        return "group \(Int(volumeGroup.bounds.width))x\(Int(volumeGroup.bounds.height)) [\(parts.joined(separator: "; "))]"
    }

    private func findGroups(in root: UIView) {
        let now = CACurrentMediaTime()
        guard now - lastSearch > 0.5 else { return }
        lastSearch = now
        playbackGroup = Self.find(in: root) { Self.className($0).hasSuffix("PlaybackControlsView") }
        volumeGroup = Self.find(in: root) { Self.className($0).hasSuffix("VolumeControlsView") }
        volumeRestWidth = nil
        if let playbackGroup {
            log.info("found \(Self.className(playbackGroup)) volume=\(volumeGroup.map(Self.className) ?? "none")")
        }
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

    private static func collect(in view: UIView, into names: inout Set<String>) {
        let name = className(view)
        if name.contains("Controls") || name.contains("Chrome") { names.insert(name) }
        view.subviews.forEach { collect(in: $0, into: &names) }
    }

    // MARK: Fallback

    private func installFallback() {
        guard allowsFallback, fallbackTap == nil, let root else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(fallbackTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = SimultaneousDelegate.shared
        root.addGestureRecognizer(tap)
        fallbackTap = tap
        // AVKit's chrome wasn't recognised: record its control classes to match a new AVKit.
        var names = Set<String>()
        Self.collect(in: root, into: &names)
        log.notice("AVKit chrome not found; fallback tap. controls: \(names.sorted().joined(separator: ", "))")
    }

    private func removeFallback() {
        guard let fallbackTap else { return }
        fallbackTap.view?.removeGestureRecognizer(fallbackTap)
        self.fallbackTap = nil
        fallbackHide?.cancel()
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
