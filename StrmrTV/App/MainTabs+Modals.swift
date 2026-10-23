import SwiftUI
import UIKit

/// The modals a card's long-press menu opens over every tab: Add to List… and the series
/// watch-state screen.
///
/// A context-menu action sets the item at once, but UIKit presents the modal only after
/// the menu's close animation, most of a second later. In that gap focus is on the closing
/// menu (or nowhere), and a Menu press went to the tab's NavigationStack, which popped the
/// page (a list grid, say); the modal then opened over the page below. No
/// view's `onExitCommand` sees that press, so `LongPressModalGate` catches Menu at the
/// window until the modal has focus, and cancels the modal instead.
struct LongPressModals: ViewModifier {
    @ObservedObject var customLists: CustomListsStore
    @ObservedObject var titles: TitleStateStore

    private var requested: Bool { customLists.picking != nil || titles.watchStateTarget != nil }

    func body(content: Content) -> some View {
        content
            .onChange(of: requested, initial: true) { _, requested in
                LongPressModalGate.shared.update(requested: requested) { [customLists, titles] in
                    customLists.picking = nil
                    titles.watchStateTarget = nil
                }
            }
            .fullScreenCover(item: $titles.watchStateTarget) { series in
                SeriesWatchStateSheet(series: series).environmentObject(titles)
            }
            .sheet(item: $customLists.picking) { target in
                AddToListSheet(target: target).environmentObject(customLists)
            }
    }
}

/// While a long-press modal is asked for, a Menu press that arrives before the modal is on
/// screen calls it off rather than reaching the page underneath. (SwiftUI's `onAppear` for
/// the modal's content fires long before it is on screen, so the check is focus instead.)
@MainActor
final class LongPressModalGate: NSObject, UIGestureRecognizerDelegate {
    static let shared = LongPressModalGate()

    private var cancel: () -> Void = {}
    private var recognizers: [ObjectIdentifier: UITapGestureRecognizer] = [:]

    func update(requested: Bool, cancel: @escaping () -> Void) {
        self.cancel = cancel
        if requested { installRecognizers() }
        for recognizer in recognizers.values { recognizer.isEnabled = requested }
    }

    private func installRecognizers() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where recognizers[ObjectIdentifier(window)] == nil {
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
                recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
                recognizer.delegate = self
                recognizer.isEnabled = false
                window.addGestureRecognizer(recognizer)
                recognizers[ObjectIdentifier(window)] = recognizer
            }
        }
    }

    @objc private func menuPressed() { cancel() }

    /// Only until the modal has focus: in the gap, focus is still on the closing menu's
    /// cell (or nowhere). Once the modal is up its own Menu handling runs, the New List
    /// alert and its keyboard included.
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let window = recognizer.view as? UIWindow else { return false }
        // SwiftUI's focus items aren't all views, so walk focus environments, not superviews.
        var environment: UIFocusEnvironment? = UIFocusSystem.focusSystem(for: window)?.focusedItem
        if environment == nil { return true }
        while let current = environment {
            if String(describing: type(of: current)).contains("ContextMenu") { return true }
            environment = current.parentFocusEnvironment
        }
        return false
    }

    /// The NavigationStack's Menu tap (which pops the page) waits for this one.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard let tap = other as? UITapGestureRecognizer, tap !== gestureRecognizer else { return false }
        return tap.allowedPressTypes.contains(NSNumber(value: UIPress.PressType.menu.rawValue))
    }
}
