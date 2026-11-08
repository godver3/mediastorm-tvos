#if os(iOS)
import SwiftUI

/// A strip under the status bar while the signed-in app (or offline Downloads) can't reach
/// the server: "You're Offline" with a way into Downloads, or "Can't Reach Server" with the
/// retry countdown; "Back Online" for a moment once it answers again.
struct MobileConnectionBanner: View {
    @ObservedObject private var connection = MobileConnection.shared
    @ObservedObject private var session = AppSession.shared
    /// Shown over offline Downloads: no Downloads button, and a hint once the app can be used.
    var inDownloads = false

    var body: some View {
        Group {
            if let content {
                HStack(spacing: 12) {
                    Image(systemName: content.symbol)
                        .font(.title3)
                        .foregroundStyle(content.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.title).font(.subheadline.weight(.semibold))
                        content.subtitle
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    action
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
                .overlay(alignment: .bottom) { Divider() }
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("connection-banner")
            }
        }
        .animation(.snappy, value: connection.status)
        .animation(.snappy, value: connection.recoveredAt)
    }

    private struct Content {
        let symbol: String
        let tint: Color
        let title: String
        let subtitle: AnyView
    }

    private var content: Content? {
        switch connection.status {
        case .offline:
            return Content(symbol: "wifi.slash", tint: .orange, title: String(localized: "You're Offline"),
                           subtitle: AnyView(Text(inDownloads ? "Downloads play without a connection." : "Downloads are still available.")))
        case .reconnecting:
            return Content(symbol: "icloud.slash", tint: .orange, title: String(localized: "Can't Reach Server"),
                           subtitle: AnyView(MobileRetryCountdown(status: connection.status)))
        case .online:
            if connection.recoveredAt != nil || (inDownloads && session.phase == .ready) {
                return Content(symbol: "checkmark.icloud", tint: .green, title: String(localized: "Back Online"),
                               subtitle: AnyView(Text(inDownloads ? "Tap Done to return to the app." : "Connected to your server.")))
            }
            return nil
        }
    }

    @ViewBuilder
    private var action: some View {
        switch connection.status {
        case .offline where !inDownloads:
            Button("Downloads") { connection.showsOfflineDownloads = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .reconnecting(_, .some):
            Button("Retry") { connection.retryNow() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .reconnecting(_, nil):
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }
}
#endif
