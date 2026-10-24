import SwiftUI
import UIKit

extension View {
    /// Keeps `isOpen` set while a `Menu` (or context menu) is up, which SwiftUI doesn't
    /// report: while one is open focus is on the menu's own UIKit cells, so this follows focus
    /// updates and checks whether the newly focused item sits in one (as `LongPressModalGate`
    /// does).
    func tracksMenuPresence(_ isOpen: Binding<Bool>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UIFocusSystem.didUpdateNotification)) { note in
            let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
            let inMenu = MenuPresence.inMenu(context?.nextFocusedItem)
            if isOpen.wrappedValue != inMenu { isOpen.wrappedValue = inMenu }
        }
    }
}

@MainActor
private enum MenuPresence {
    /// SwiftUI's focus items aren't all views, so this walks focus environments, not superviews.
    static func inMenu(_ item: UIFocusItem?) -> Bool {
        var environment: UIFocusEnvironment? = item
        while let current = environment {
            if String(describing: type(of: current)).contains("ContextMenu") { return true }
            environment = current.parentFocusEnvironment
        }
        return false
    }
}
