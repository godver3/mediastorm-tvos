import SwiftUI
import UIKit

/// Menu never sends the app home just because nothing had focus when it was pressed.
///
/// UIKit sends a press to the focused item and up its responder chain. With focus nowhere
/// (or on the tab bar) no view's `onExitCommand` and no NavigationStack's Menu tap sees
/// the press, and it falls through to the system, which leaves the app. That happens
/// while a screen is being swapped in (a profile picked, a PIN accepted: Home is still
/// building), while a cover animates in or out, and on a pushed page that shows only a
/// spinner while it loads (a game, a list, a library show). Just after a profile opens,
/// focus sits on the tab bar until Home has rows to take it, and Menu there leaves the
/// app as it would at any tab's root. A tap recognizer on the window catches Menu in
/// those cases: a pushed page goes back, anything else drops the press. With focus in
/// place, the player up or a modal open, it stays out of the way.
@MainActor
final class UnfocusedMenuGuard: NSObject, UIGestureRecognizerDelegate {
    static let shared = UnfocusedMenuGuard()

    /// The stack the press pops, found when the recognizer is asked to begin; nil drops it.
    private weak var target: UINavigationController?
    /// Until then (or until focus first leaves the tab bar), Menu on the tab bar is dropped:
    /// the tabs have just been built and focus hasn't reached the page yet.
    private var settlingUntil: Date?
    private var focusObserver: NSObjectProtocol?

    /// The tabs were just built (a profile picked): a Menu on the tab bar before focus has
    /// reached the page was meant for the screen before, not to leave the app. Capped, so
    /// a Home that never loads can still be left.
    func tabsAppeared() {
        settlingUntil = Date().addingTimeInterval(10)
        guard focusObserver == nil else { return }
        focusObserver = NotificationCenter.default.addObserver(
            forName: UIFocusSystem.didUpdateNotification, object: nil, queue: .main
        ) { note in
            let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
            let next = context?.nextFocusedItem
            MainActor.assumeIsolated {
                guard let next, !Self.focus(next, reaches: { $0 is UITabBar }) else { return }
                self.stopSettling()
            }
        }
    }

    private func stopSettling() {
        settlingUntil = nil
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = nil
    }

    fileprivate func install(on window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === self }) else { return }
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
        recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
    }

    @objc private func menuPressed() {
        let log = AppLog(category: "navigation")
        guard let target else { return log.debug("Menu with nothing (or only the tab bar) focused: dropped") }
        log.debug("Menu with no focus on the page: going back")
        target.popViewController(animated: true)
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        target = nil
        guard let window = recognizer.view as? UIWindow, let root = window.rootViewController,
              !LongPressModalGate.shared.requested else { return false }
        // A modal or the player that is up handles its own presses (the player's aren't
        // always through focus); one still animating in or out has nothing focused yet.
        let presented = root.presentedViewController
        if let presented, !presented.isBeingPresented, !presented.isBeingDismissed { return false }
        let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem
        if presented == nil, let navigation = Self.pushedStack(in: root),
           !Self.focus(focused, reaches: { $0 === navigation }) {
            target = navigation
            return true
        }
        if let settlingUntil, settlingUntil > Date(), presented == nil, Self.focus(focused, reaches: { $0 is UITabBar }) {
            return true
        }
        return focused == nil
    }

    /// Any other Menu tap (the tab bar's, say) waits for this one.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard let tap = other as? UITapGestureRecognizer, tap !== gestureRecognizer else { return false }
        return tap.allowedPressTypes.contains(NSNumber(value: UIPress.PressType.menu.rawValue))
    }

    /// SwiftUI's focus items aren't all views, so this walks focus environments, not superviews.
    private static func focus(_ item: UIFocusItem?, reaches match: (UIFocusEnvironment) -> Bool) -> Bool {
        var environment: UIFocusEnvironment? = item
        while let current = environment {
            if match(current) { return true }
            environment = current.parentFocusEnvironment
        }
        return false
    }

    /// The innermost on-screen navigation stack with a page pushed over its root. Tabs
    /// not shown are out of the window, so only the selected tab's stack is found.
    private static func pushedStack(in controller: UIViewController) -> UINavigationController? {
        guard controller.viewIfLoaded?.window != nil else { return nil }
        for child in controller.children {
            if let found = pushedStack(in: child) { return found }
        }
        if let navigation = controller as? UINavigationController, navigation.viewControllers.count > 1 {
            return navigation
        }
        return nil
    }
}

extension View {
    /// Makes sure the window this view is in keeps Menu from leaving the app when nothing has focus.
    func guardsUnfocusedMenu() -> some View {
        background(UnfocusedMenuGuardProbe().frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true))
    }
}

private struct UnfocusedMenuGuardProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if let window { UnfocusedMenuGuard.shared.install(on: window) }
        }
    }
}
