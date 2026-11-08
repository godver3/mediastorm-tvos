#if os(iOS)
import SwiftUI

/// Placeholder until the Downloads screen is ported.
struct MobileDownloadsView: View {
    var body: some View {
        MobilePendingScreen(title: "Downloads", systemImage: "arrow.down.circle")
    }
}
#endif
