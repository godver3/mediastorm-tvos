#if os(iOS)
import AVKit
import UIKit

/// App-level iOS hooks. Orientation follows the Expo app: a phone stays portrait everywhere
/// except in a player (the engine player keeps the viewer's landscape / portrait / follow-device
/// pick, other AVKit players such as trailers turn with the device); an iPad turns freely.
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

    /// The download manager re-attaches to its background session and moves the queue on as it
    /// starts, so it starts with the app rather than with the first Downloads or details page.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = DownloadManager.shared
        return true
    }

    /// The system relaunched the app for the downloads' background session: re-create it so
    /// the finished transfers are delivered, and tell the system once they have been.
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadSession.identifier else { return completionHandler() }
        DownloadManager.shared.session.setBackgroundCompletion(completionHandler)
    }
}
#endif
