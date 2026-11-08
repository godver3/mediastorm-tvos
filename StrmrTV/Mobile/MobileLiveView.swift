#if os(iOS)
import SwiftUI

/// Placeholder until the Live screen is ported.
struct MobileLiveView: View {
    var body: some View {
        MobilePendingScreen(title: "Live", systemImage: "dot.radiowaves.left.and.right")
    }
}
#endif
