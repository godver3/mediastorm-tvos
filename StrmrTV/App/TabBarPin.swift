import SwiftUI
import UIKit

/// Keeps the menu up while a page scrolls. tvOS hides the
/// top tab bar, and the side menu's collapsed pill, once the page's content scroll view
/// leaves its top. Each style tracks that scroll view its own way, so each gets a scroll view
/// that never scrolls to track instead, and the page's real scroll views move freely:
///
/// - The top bar is UIKit's `UITabBarController`, which tracks the view controller's
///   `contentScrollView(for: .top)` (a heuristic when none is set). `TabBarPin` sets it, on
///   the page's view controller, to an invisible scroll view (as Classic Home's
///   never-scrolling outer scroll view does, without changing the page's layout).
/// - The side menu (`.sidebarAdaptable`) is drawn by SwiftUI without per-tab view
///   controllers and ignores that; it follows a scroll view of the page's own (on the
///   simulator: the largest, the front-most on a tie, not the first). `pinsSideMenu` lays an
///   invisible, never-scrolling, full-screen one in front of the page (hit testing off, so
///   focus and touches go through). Set on each tab's navigation stack and on the pages
///   pushed on them, whose scroll views fill the screen too (Home, details).
struct TabBarPin: UIViewRepresentable {
    func makeUIView(context: Context) -> PinView { PinView() }
    func updateUIView(_ view: PinView, context: Context) {}

    final class PinView: UIView {
        private static let log = AppLog(category: "menustyle")
        /// The scroll view the tab bar tracks: never scrolls, never seen.
        private let anchor = UIScrollView()
        private weak var pinned: UIViewController?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            anchor.isScrollEnabled = false
            anchor.isUserInteractionEnabled = false
            anchor.alpha = 0
            addSubview(anchor)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                if let pinned, pinned.contentScrollView(for: .top) === anchor { pinned.setContentScrollView(nil, for: .top) }
                pinned = nil
                return
            }
            // After the hosting controllers are in place.
            DispatchQueue.main.async { [weak self] in self?.pin() }
        }

        /// The page's view controller: the one whose parent is the navigation stack (or the
        /// tab bar controller, for a tab without one).
        private func pin() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            var page: UIViewController?
            while let next = responder?.next {
                if let controller = next as? UIViewController {
                    page = controller
                    if controller.parent is UINavigationController || controller.parent is UITabBarController { break }
                }
                responder = next
            }
            guard let page, page !== pinned else { return }
            page.setContentScrollView(anchor, for: .top)
            pinned = page
            Self.log.debug("tab bar pinned on \(String(describing: type(of: page)))")
        }
    }
}

extension View {
    /// Keeps the top tab bar up however far this page scrolls.
    func pinsTabBar() -> some View {
        background(TabBarPin().frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true))
    }

    /// With the side menu, keeps its collapsed pill up at any scroll position.
    /// Nothing with the top bar, which is left as it was.
    func pinsSideMenu() -> some View { modifier(SideMenuPin()) }
}

private struct SideMenuPin: ViewModifier {
    @Environment(\.sidebarInset) private var sidebarInset

    func body(content: Content) -> some View {
        ZStack {
            content
            if sidebarInset > 0 {
                ScrollView(.vertical) { Color.clear.frame(height: 1) }
                    .scrollDisabled(true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .ignoresSafeArea()
            }
        }
    }
}
