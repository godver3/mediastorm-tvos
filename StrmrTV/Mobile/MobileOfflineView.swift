#if os(iOS)
import SwiftUI

/// The startup error on the phone: the device is offline, or the server didn't answer. It
/// retries by itself (`MobileConnection`) and offers Downloads meanwhile, as the Expo app's
/// restricted offline mode does, instead of stopping at "Couldn't Connect".
struct MobileOfflineView: View {
    @ObservedObject private var session = AppSession.shared
    @ObservedObject private var connection = MobileConnection.shared
    @ObservedObject private var monitor = MobileNetworkMonitor.shared
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: monitor.isDeviceOffline ? "wifi.slash" : "icloud.slash")
            } description: {
                VStack(spacing: 8) {
                    Text(detail)
                    if !monitor.isDeviceOffline, !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(.tertiary)
                    }
                    MobileRetryCountdown(status: connection.status)
                        .foregroundStyle(.secondary)
                }
            } actions: {
                Button {
                    connection.showsOfflineDownloads = true
                } label: {
                    Label("Open Downloads", systemImage: "arrow.down.circle")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Try Again") { connection.retryNow() }
                    .disabled(isRetrying)
                Button("Change Server") { session.changeServer() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MobileConnectionSettingsView()
                    } label: {
                        Label("Connection", systemImage: "network")
                    }
                }
            }
        }
    }

    private var title: String {
        if monitor.isDeviceOffline { return String(localized: "You're Offline") }
        let host = session.isRemote ? String(localized: "Your Server") : session.serverURL?.host() ?? String(localized: "the Server")
        return String(localized: "Can't Reach \(host)")
    }

    private var detail: String {
        if monitor.isDeviceOffline {
            return String(localized: "Connect to Wi-Fi or cellular data. Your downloads are still available.")
        }
        return String(localized: "The server didn't answer. MediaStorm keeps trying; your downloads are still available.")
    }

    private var isRetrying: Bool {
        if case .reconnecting(_, nil) = connection.status { return true }
        return false
    }
}

/// "Retrying in 8 s" / "Reconnecting…" under the offline screen and in the banner.
struct MobileRetryCountdown: View {
    let status: MobileConnection.Status

    var body: some View {
        switch status {
        case let .reconnecting(_, next?):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = max(1, Int(next.timeIntervalSince(context.date).rounded(.up)))
                Text("Retrying in \(seconds) s")
                    .monospacedDigit()
            }
        case .reconnecting(_, nil):
            Text("Reconnecting…")
        case .offline:
            Text("Waiting for a network connection")
        case .online:
            EmptyView()
        }
    }
}

/// "Connecting…", with a way into Downloads when it takes a while (the Expo app opens in its
/// restricted offline mode when startup times out) or the device has no network.
struct MobileStartingView: View {
    @ObservedObject private var connection = MobileConnection.shared
    @ObservedObject private var monitor = MobileNetworkMonitor.shared
    @State private var slow = false

    var body: some View {
        VStack(spacing: 24) {
            ProgressView("Connecting…")
            if slow || monitor.isDeviceOffline {
                Button {
                    connection.showsOfflineDownloads = true
                } label: {
                    Label("Use Downloads Meanwhile", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: slow)
        .task {
            try? await Task.sleep(for: .seconds(8))
            slow = true
        }
    }
}

/// Downloads without a server, over the startup screens or the signed-in app. Its banner says
/// when the server is back; Done returns to wherever the app is by then.
struct MobileOfflineDownloads: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MobileDownloadsView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    MobileConnectionBanner(inDownloads: true)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
#endif
