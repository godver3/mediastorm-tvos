#if os(iOS)
import UIKit

/// Phone player behaviour: landscape while the player is up (or portrait, the viewer's pick; an
/// iPad follows the device), and a close button on the software (dav1d / VP9) route, whose surface
/// hides AVKit's touch controls, for players without their own touch transport (live, recordings).
extension EnginePlayerViewController {
    private static let closeButtonTag = 0x5354_524D  // "STRM"

    /// Rotates into the player's orientation as it appears (a portrait-locked phone included).
    func enterPreferredOrientation() {
        setNeedsUpdateOfSupportedInterfaceOrientations()
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: Self.phoneOrientation)) { _ in }
    }

    /// Back to portrait for the app underneath once the player has closed (a phone; an iPad's app
    /// turns with the device).
    static func restorePortrait() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        scene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    }

    /// Adds the close button (hidden until the software surface mounts).
    func installTouchClose() {
        let button = UIButton(configuration: {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(weight: .semibold))
            config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
            config.baseForegroundColor = .white
            config.cornerStyle = .capsule
            return config
        }(), primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        button.tag = Self.closeButtonTag
        button.isHidden = true
        button.accessibilityLabel = String(localized: "Close")
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    /// Shows the close button while the software surface (with no AVKit chrome) is up.
    func updateTouchClose(softwareMounted: Bool) {
        guard let button = view.viewWithTag(Self.closeButtonTag) else { return }
        button.isHidden = !softwareMounted || hasTouchTransport
        view.bringSubviewToFront(button)
    }
}
#endif
