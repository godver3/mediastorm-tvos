import AVKit
import UIKit

extension UIWindow {
    /// The TV's Match Content setting (Settings › Video and Audio): when on, the engine switches
    /// the display to the content's dynamic range and frame rate. iOS screens don't switch modes.
    var displayCriteriaMatchingEnabled: Bool {
        #if os(tvOS)
        avDisplayManager.isDisplayCriteriaMatchingEnabled
        #else
        false
        #endif
    }
}
