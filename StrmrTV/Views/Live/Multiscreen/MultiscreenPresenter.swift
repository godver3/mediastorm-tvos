import Combine
import SwiftUI
import UIKit

/// Opens multiscreen over whatever is on screen: from the Live tab, or in place of the
/// full-screen live player (`LivePlayerViewController.addScreen`).
@MainActor
enum MultiscreenPresenter {
    static func open(_ entry: MultiscreenEntry, over presenter: UIViewController? = nil) {
        guard let top = presenter.map(topmost) ?? topViewController(), !(top is MultiscreenHostController) else { return }
        top.present(MultiscreenHostController(entry: entry), animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.windows.first(where: \.isKeyWindow)?.rootViewController.map(topmost)
    }

    private static func topmost(_ controller: UIViewController) -> UIViewController {
        var top = controller
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

/// Hosts `MultiscreenView` over the app, keeps the screen awake while it is up, and closes
/// once the controller has released every stream. Dismissed any other way, it still stops
/// the players and releases the sessions.
final class MultiscreenHostController: UIHostingController<MultiscreenView> {
    private let controller: MultiscreenController
    private var finished: AnyCancellable?

    init(entry: MultiscreenEntry) {
        controller = MultiscreenController(entry: entry)
        super.init(rootView: MultiscreenView(controller: controller))
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        finished = controller.$finished
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.dismiss(animated: true) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Several AVPlayerLayers outside AVKit don't hold the screensaver off on their own.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        guard !controller.finished else { return }
        let controller = controller
        Task {
            try? await controller.session.close()
            controller.shutdown()
        }
    }
}
