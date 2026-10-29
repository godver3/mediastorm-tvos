import UIKit

/// Logs where focus is once the player has closed, and where it moves for a minute after.
/// An app left unresponsive after an episode ended kept its main thread answering (the
/// watchdog stayed quiet), so the remote had nothing to move: these lines show whether
/// focus was lost, stuck on something off screen, or under a controller that never left.
@MainActor
enum PlayerCloseFocusLog {
    private static let log = AppLog(category: "focus")
    private static let watchFor: TimeInterval = 60
    private static let maxMoves = 8
    private static var observer: FocusObserver?
    private static var watchUntil = Date.distantPast
    private static var moves = 0

    static func playerClosed() {
        log.notice("player closed: \(snapshot())")
        Task {
            try? await Task.sleep(for: .seconds(3))
            log.notice("3 s after player close: \(snapshot())")
        }
        watchUntil = Date().addingTimeInterval(watchFor)
        moves = 0
        guard observer == nil else { return }
        let observer = FocusObserver()
        NotificationCenter.default.addObserver(observer, selector: #selector(FocusObserver.focusDidUpdate(_:)),
                                               name: UIFocusSystem.didUpdateNotification, object: nil)
        self.observer = observer
    }

    /// Focus updates are posted on the main thread; a selector observer takes them there
    /// without handing the (non-Sendable) notification across isolation.
    @MainActor
    private final class FocusObserver: NSObject {
        @objc func focusDidUpdate(_ note: Notification) {
            let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
            PlayerCloseFocusLog.focusMoved(to: context?.nextFocusedItem)
        }
    }

    fileprivate static func focusMoved(to item: UIFocusItem?) {
        guard Date() < watchUntil, moves < maxMoves else { return stopWatching() }
        moves += 1
        log.info("focus moved to \(describe(item))")
    }

    private static func stopWatching() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// The focused item, the presented controller chain from the key window's root, and
    /// how many windows the scene has.
    private static func snapshot() -> String {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let window = scene?.windows.first(where: \.isKeyWindow) else {
            return "no key window (windows=\(scene?.windows.count ?? 0))"
        }
        var chain: [String] = []
        var vc = window.rootViewController
        while let current = vc {
            chain.append(typeName(current) + (current.isBeingDismissed ? " (dismissing)" : ""))
            vc = current.presentedViewController
        }
        let focused = UIFocusSystem.focusSystem(for: window)?.focusedItem
        return "focused=\(describe(focused)) controllers=\(chain.joined(separator: " > ")) "
            + "windows=\(scene?.windows.count ?? 0)"
    }

    private static func describe(_ item: UIFocusItem?) -> String {
        guard let item else { return "nothing" }
        var text = typeName(item)
        // SwiftUI's focus items aren't views; their frame (screen points) places them.
        if let label = (item as? NSObject)?.accessibilityLabel, !label.isEmpty { text += " \"\(label)\"" }
        let frame = item.frame.integral
        text += " at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
        if let view = item as? UIView {
            if view.window == nil { text += " (off window)" }
            if view.isHidden || view.alpha == 0 { text += " (hidden)" }
        }
        return text
    }

    /// The type's name without generic arguments (SwiftUI's hosting controllers run long).
    private static func typeName(_ value: Any) -> String {
        let name = String(describing: type(of: value))
        return name.firstIndex(of: "<").map { String(name[..<$0]) } ?? name
    }
}
