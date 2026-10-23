import SwiftUI
import UIKit

extension NativeChrome {
    /// The Settings menu's "Switch Source…" row. It opens `sourcePage` rather
    /// than a submenu: a transport-bar menu row fits about twenty characters, too few for a
    /// release name and its details, and AVKit shows a deferred (searched-on-open) submenu as an
    /// empty panel.
    static func switchSourceAction(onOpen: @escaping @MainActor () -> Void) -> UIAction {
        UIAction(title: String(localized: "Switch Source…"),
                 image: UIImage(systemName: "arrow.triangle.2.circlepath")) { _ in
            // Once the menu has gone: presenting while it closes is dropped (as Search Online…).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onOpen() }
        }
    }

    /// The sources as a wide full-screen list over the player (`SourceSwitchView`). The page
    /// dismisses itself first, then calls `onPick` with another source, or `onCancel` for Menu
    /// or the playing source.
    static func sourcePage(heading: String, rows: [SourceSwitchView.Row],
                           onPick: @escaping @MainActor (SourceSwitch.Option) -> Void,
                           onCancel: @escaping @MainActor () -> Void) -> UIViewController {
        weak var page: UIViewController?
        let host = UIHostingController(rootView: SourceSwitchView(
            heading: heading, rows: rows,
            onPick: { option in page?.dismiss(animated: true) { onPick(option) } },
            onClose: { page?.dismiss(animated: true) { onCancel() } }))
        page = host
        host.modalPresentationStyle = .overFullScreen
        host.view.backgroundColor = .clear
        return host
    }
}
