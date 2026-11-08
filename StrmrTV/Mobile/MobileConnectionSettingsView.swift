#if os(iOS)
import SwiftUI

/// Server connection preferences (home network vs remote access, network status); linked from
/// Settings. Placeholder until the network-handling port fills it in.
struct MobileConnectionSettingsView: View {
    var body: some View {
        MobilePendingScreen(title: "Connection", systemImage: "network")
    }
}
#endif
