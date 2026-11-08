#if !os(tvOS)
import AVKit
import ObjectiveC
import SwiftUI

// iOS stand-ins for the tvOS-only API the shared screens use, so a screen compiles on both
// platforms unchanged. Focus and remote modifiers are inert on iOS (touch has no focus engine
// or Menu button); iOS-specific behaviour belongs in the screen's own `+iOS` file.

/// SwiftUI's `MoveCommandDirection` is macOS / tvOS only.
enum MoveCommandDirection: Sendable {
    case up, down, left, right
}

extension View {
    /// tvOS focus sections have no meaning without a focus engine.
    func focusSection() -> some View { self }

    /// The Menu button; on iOS, back is the navigation stack's own gesture and button.
    func onExitCommand(perform action: (() -> Void)?) -> some View { self }

    /// The remote's Play/Pause button.
    func onPlayPauseCommand(perform action: (() -> Void)?) -> some View { self }

    /// Default-focus hints for the focus engine.
    func prefersDefaultFocus(_ prefersDefaultFocus: Bool = true, in namespace: Namespace.ID) -> some View { self }
    func focusScope(_ namespace: Namespace.ID) -> some View { self }

    /// Remote arrows; touch screens scroll instead.
    func onMoveCommand(perform action: ((MoveCommandDirection) -> Void)?) -> some View { self }
}

// AVPlayerViewController's tvOS transport-bar API. Stored here so the shared player code can
// keep reading what it set (the skip action feeds the software HUD, the menus its own bar).
private enum ShimKey {
    nonisolated(unsafe) static var contextualActions: UInt8 = 0
    nonisolated(unsafe) static var transportBarCustomMenuItems: UInt8 = 0
    nonisolated(unsafe) static var customInfoViewControllers: UInt8 = 0
}

extension AVPlayerViewController {
    var contextualActions: [UIAction] {
        get { objc_getAssociatedObject(self, &ShimKey.contextualActions) as? [UIAction] ?? [] }
        set { objc_setAssociatedObject(self, &ShimKey.contextualActions, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var transportBarCustomMenuItems: [UIMenuElement] {
        get { objc_getAssociatedObject(self, &ShimKey.transportBarCustomMenuItems) as? [UIMenuElement] ?? [] }
        set {
            objc_setAssociatedObject(self, &ShimKey.transportBarCustomMenuItems, newValue,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    var customInfoViewControllers: [UIViewController] {
        get { objc_getAssociatedObject(self, &ShimKey.customInfoViewControllers) as? [UIViewController] ?? [] }
        set {
            objc_setAssociatedObject(self, &ShimKey.customInfoViewControllers, newValue,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// iOS has no display-mode switching (HDR / frame-rate match), so nothing to opt out of.
    var appliesPreferredDisplayCriteriaAutomatically: Bool {
        get { false }
        set {}
    }
}
#endif
