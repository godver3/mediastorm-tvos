import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Counts remote input (button presses, and touches on the remote's touch surface), so a
/// timer can start over on any press (the Top Carousel's auto-advance).
/// A gesture recognizer on the window sees every press and touch on their way to the
/// focused view and fails at once, so it never delays, cancels or takes any of them.
@MainActor
final class RemoteActivity: ObservableObject {
    static let shared = RemoteActivity()

    /// Goes up by one on every press or touch.
    @Published private(set) var count = 0

    fileprivate func record() { count &+= 1 }

    fileprivate func install(on window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0 is PressObserver }) else { return }
        window.addGestureRecognizer(PressObserver())
        AppLog(category: "remote").debug("observing remote input")
    }
}

extension View {
    /// Makes sure the window this view is in reports its remote input to `RemoteActivity`.
    func observesRemoteActivity() -> some View {
        background(RemoteActivityProbe().frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true))
    }
}

private struct RemoteActivityProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if let window { RemoteActivity.shared.install(on: window) }
        }
    }
}

private final class PressObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
        // The base class takes no presses unless told which.
        let types: [UIPress.PressType] = [.upArrow, .downArrow, .leftArrow, .rightArrow, .select, .menu, .playPause,
                                          .pageUp, .pageDown]
        allowedPressTypes = types.map { NSNumber(value: $0.rawValue) }
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        RemoteActivity.shared.record()
        state = .failed
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        RemoteActivity.shared.record()
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
