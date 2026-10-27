import SwiftUI

/// Settings › Playback: forgets the live sources remembered as needing HLS
/// (`LiveHLSPreference`), so their next tune tries the source's own setting again.
struct LiveHLSResetRow: View {
    @State private var result: String?

    var body: some View {
        Button {
            result = Self.resultText(LiveHLSPreference.resetAll())
        } label: {
            LabeledContent("Try Direct Again") { Text(result ?? "") }
        }
        .accessibilityHint(Text("Forgets live sources switched to HLS, so they try their own stream format on the next tune"))
    }

    private static func resultText(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Nothing to reset")
        case 1: String(localized: "Reset 1 source")
        default: String(localized: "Reset \(count) sources")
        }
    }
}
