#if os(iOS)
import AVKit
import UIKit

/// App-level iOS hooks. Orientation follows the Expo app: a phone stays portrait everywhere
/// except in a player (the engine player keeps the viewer's landscape / portrait pick, other
/// AVKit players such as trailers turn with the device); an iPad turns freely.
final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        var controller = window?.rootViewController?.presentedViewController
        while let current = controller {
            if current is EnginePlayerViewController { return EnginePlayerViewController.playerOrientations }
            if current is AVPlayerViewController { return .allButUpsideDown }
            controller = current.presentedViewController
        }
        return .portrait
    }
}
#endif
