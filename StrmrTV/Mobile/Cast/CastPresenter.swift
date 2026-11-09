#if os(iOS)
import SwiftUI
import UIKit

/// Presents the device picker and the remote as UIKit sheets on the top view controller, so
/// they open the same way from a SwiftUI page and from the full-screen player.
@MainActor
enum CastPresenter {
    private static weak var remote: UIViewController?
    private static weak var picker: UIViewController?

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }

    /// The picker; `onPick` runs once it has closed.
    static func showPicker(from presenter: UIViewController? = nil, onPick: @escaping @MainActor (CastDevice) -> Void) {
        guard picker == nil, let presenter = presenter ?? topViewController() else { return }
        // Weak: the picker's closures are held by the controller's own root view, and a strong
        // reference kept it (and `picker`) alive after it closed, so it never opened again.
        weak var controller: UIViewController?
        let view = CastDevicePicker { device in
            controller?.dismiss(animated: true) { onPick(device) }
        } onShowRemote: {
            controller?.dismiss(animated: true) { showRemote() }
        }
        let hosting = UIHostingController(rootView: view)
        controller = hosting
        sheet(hosting, detents: [.medium(), .large()])
        picker = hosting
        presenter.present(hosting, animated: true)
    }

    /// The "Casting to …" remote, unless it is already up.
    static func showRemote() {
        guard remote == nil, let presenter = topViewController() else { return }
        let hosting = UIHostingController(rootView: CastRemoteView())
        sheet(hosting, detents: [.large()])
        remote = hosting
        presenter.present(hosting, animated: true)
    }

    static func dismissRemote() {
        guard let current = remote else { return }
        remote = nil
        if current.presentingViewController != nil { current.dismiss(animated: true) }
    }

    private static func sheet(_ controller: UIViewController, detents: [UISheetPresentationController.Detent]) {
        controller.modalPresentationStyle = .pageSheet
        controller.overrideUserInterfaceStyle = .dark
        if let sheet = controller.sheetPresentationController {
            sheet.detents = detents
            sheet.prefersGrabberVisible = true
        }
    }

    // MARK: The cast glyph

    /// The standard cast icon (a screen with broadcast arcs), as a template image; SF Symbols has
    /// no equivalent. Drawn on a 24-point grid and scaled to `pointSize`.
    nonisolated static func castIcon(pointSize: CGFloat = 22) -> UIImage {
        let scale = pointSize / 24
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize))
        let image = renderer.image { _ in
            let path = UIBezierPath()
            // Screen outline, open at the bottom left where the arcs sit.
            path.move(to: CGPoint(x: 21, y: 3))
            path.addLine(to: CGPoint(x: 3, y: 3))
            path.addCurve(to: CGPoint(x: 1, y: 5), controlPoint1: CGPoint(x: 1.9, y: 3), controlPoint2: CGPoint(x: 1, y: 3.9))
            path.addLine(to: CGPoint(x: 1, y: 8))
            path.addLine(to: CGPoint(x: 3, y: 8))
            path.addLine(to: CGPoint(x: 3, y: 5))
            path.addLine(to: CGPoint(x: 21, y: 5))
            path.addLine(to: CGPoint(x: 21, y: 19))
            path.addLine(to: CGPoint(x: 14, y: 19))
            path.addLine(to: CGPoint(x: 14, y: 21))
            path.addLine(to: CGPoint(x: 21, y: 21))
            path.addCurve(to: CGPoint(x: 23, y: 19), controlPoint1: CGPoint(x: 22.1, y: 21), controlPoint2: CGPoint(x: 23, y: 20.1))
            path.addLine(to: CGPoint(x: 23, y: 5))
            path.addCurve(to: CGPoint(x: 21, y: 3), controlPoint1: CGPoint(x: 23, y: 3.9), controlPoint2: CGPoint(x: 22.1, y: 3))
            path.close()
            // Dot.
            path.move(to: CGPoint(x: 1, y: 18))
            path.addLine(to: CGPoint(x: 1, y: 21))
            path.addLine(to: CGPoint(x: 4, y: 21))
            path.addCurve(to: CGPoint(x: 1, y: 18), controlPoint1: CGPoint(x: 4, y: 19.34), controlPoint2: CGPoint(x: 2.66, y: 18))
            path.close()
            // Arcs.
            for (radius, width) in [(CGFloat(6), CGFloat(2)), (10, 2)] {
                let inner = radius - width
                path.move(to: CGPoint(x: 1, y: 21 - radius))
                path.addArc(withCenter: CGPoint(x: 1, y: 21), radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
                path.addLine(to: CGPoint(x: 1 + inner, y: 21))
                path.addArc(withCenter: CGPoint(x: 1, y: 21), radius: inner, startAngle: 0, endAngle: -.pi / 2, clockwise: false)
                path.close()
            }
            path.apply(CGAffineTransform(scaleX: scale, y: scale))
            UIColor.black.setFill()
            path.fill()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

extension Image {
    /// The cast glyph (`CastPresenter.castIcon`) as a template.
    static func castIcon(pointSize: CGFloat = 20) -> Image {
        Image(uiImage: CastPresenter.castIcon(pointSize: pointSize)).renderingMode(.template)
    }
}
#endif
