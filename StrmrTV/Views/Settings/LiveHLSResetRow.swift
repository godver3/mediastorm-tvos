import SwiftUI

/// Settings › Playback: forgets the live sources remembered as needing HLS
/// (`LiveHLSPreference`), so their next tune tries the source's own setting again.
struct LiveHLSResetRow: View {
    @State private var result: String?

    var body: some View {
        Button {
            let count = LiveHLSPreference.resetAll()
            result = count == 0 ? String(localized: "Nothing to reset") : String(localized: "Reset")
        } label: {
            LabeledContent("Reset Live TV Playback") { Text(result ?? "") }
        }
        .accessibilityHint(Text("Live TV tries your provider's own stream format again on the next tune"))
    }
}
