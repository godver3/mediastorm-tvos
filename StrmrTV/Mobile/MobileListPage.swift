#if os(iOS)
import SwiftUI

/// Placeholder until the List screen is ported.
struct MobileListPage: View {
    let list: BrowseList

    var body: some View {
        MobilePendingScreen(title: "List", systemImage: "list.bullet")
    }
}
#endif
