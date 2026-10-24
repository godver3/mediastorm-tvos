import SwiftUI
import UIKit

/// The one focusable thing over the tiles. It takes the remote whole: arrows (clicks and
/// swipes), Select, a held Select and Menu go to the handlers instead of moving focus, so the
/// tiles' own geometry (`MultiscreenLayout.neighbor`) decides where an arrow goes.
struct MultiscreenRemoteCatcher: UIViewRepresentable {
    struct Handlers {
        var move: (MultiscreenDirection) -> Void
        var select: () -> Void
        var longSelect: () -> Void
        var menu: () -> Void
        /// Any other press (Play / Pause): reveals the overlay.
        var other: () -> Void
    }

    let handlers: Handlers

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.handlers = handlers
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.handlers = handlers
    }

    final class CatcherView: UIView {
        var handlers: Handlers?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityIdentifier = "multiscreen.tiles"
            accessibilityLabel = String(localized: "Screens")
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            hold.minimumPressDuration = 0.5
            addGestureRecognizer(hold)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            tap.require(toFail: hold)
            addGestureRecognizer(tap)
            let menu = UITapGestureRecognizer(target: self, action: #selector(menuPressed))
            menu.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
            addGestureRecognizer(menu)
            for direction in [UISwipeGestureRecognizer.Direction.left, .right, .up, .down] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                addGestureRecognizer(swipe)
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override var canBecomeFocused: Bool { true }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var unhandled = Set<UIPress>()
            for press in presses {
                switch press.type {
                case .upArrow: handlers?.move(.up)
                case .downArrow: handlers?.move(.down)
                case .leftArrow: handlers?.move(.left)
                case .rightArrow: handlers?.move(.right)
                case .playPause: handlers?.other()
                default: unhandled.insert(press)
                }
            }
            if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
        }

        // The rest of a handled press stays here too, so the focus engine never sees half of one.
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let rest = presses.filter { !Self.handled.contains($0.type) }
            if !rest.isEmpty { super.pressesEnded(rest, with: event) }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let rest = presses.filter { !Self.handled.contains($0.type) }
            if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
        }

        private static let handled: Set<UIPress.PressType> = [.upArrow, .downArrow, .leftArrow, .rightArrow, .playPause]

        @objc private func tapped() { handlers?.select() }
        @objc private func menuPressed() { handlers?.menu() }

        @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state == .began { handlers?.longSelect() }
        }

        @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
            switch recognizer.direction {
            case .left: handlers?.move(.left)
            case .right: handlers?.move(.right)
            case .up: handlers?.move(.up)
            default: handlers?.move(.down)
            }
        }
    }
}
