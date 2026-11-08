#if os(iOS)
import SwiftUI

/// Download preferences (Wi-Fi only, storage, quality); linked from Settings. Placeholder until
/// the Downloads port fills it in.
struct MobileDownloadSettingsView: View {
    var body: some View {
        MobilePendingScreen(title: "Downloads", systemImage: "arrow.down.circle")
    }
}
#endif
