#if os(iOS)
import SwiftUI

/// Settings → Connection: how the phone reaches the server right now (home network, remote
/// access or a typed address), the phone's own network, the server's home-network settings
/// that drive switching, remote access status with Reconnect, and recent connection events.
/// As in the Expo app, the switching itself has no client-side mode: it follows the server's
/// "Network URL Switching" settings (web UI → Settings → Server).
struct MobileConnectionSettingsView: View {
    @ObservedObject private var session = AppSession.shared
    @ObservedObject private var connection = MobileConnection.shared
    @ObservedObject private var monitor = MobileNetworkMonitor.shared
    @ObservedObject private var selector = MobileConnectionSelector.shared
    @ObservedObject private var wifi = MobileWiFiSSID.shared
    @State private var irohRoute: IrohRoute = .detecting
    @State private var checking = false
    @State private var checkResult: String?
    @State private var journal: [MobileReconnectJournal.Entry] = []
    #if DEBUG
    @State private var fault = DebugNetworkFault.current
    #endif

    var body: some View {
        Form {
            statusSection
            deviceSection
            homeNetworkSection
            if RemoteAccess.shared.pairing != nil { remoteSection }
            Section {
                Button {
                    Task { await checkNow() }
                } label: {
                    HStack {
                        Label("Check Connection", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if checking { ProgressView() }
                    }
                }
                .disabled(checking)
                Button("Change Server…") { session.changeServer() }
            } footer: {
                if let checkResult { Text(checkResult) }
            }
            eventsSection
            #if DEBUG
            debugSection
            #endif
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            journal = MobileReconnectJournal.entries.reversed()
        }
        .task(id: session.isRemote) {
            // iroh can upgrade a relayed link to direct (or fall back) at any time.
            while !Task.isCancelled {
                await refreshIrohPath()
                try? await Task.sleep(for: IrohRoute.pollInterval)
            }
        }
        .refreshable {
            await selector.refreshSettings()
            await refreshIrohPath()
            journal = MobileReconnectJournal.entries.reversed()
        }
    }

    // MARK: Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Status") {
                iconValue(statusText, statusSymbol)
                    .foregroundStyle(connection.status == .online ? Color.green : Color.orange)
            }
            LabeledContent("Connection") {
                iconValue(routeText, routeSymbol)
            }
            if let url = session.serverURL {
                LabeledContent("Address", value: session.isRemote ? String(localized: "Remote access tunnel") : ServerAddress.display(url))
            }
            if let version = session.serverVersion?.version {
                LabeledContent("Server Version", value: version)
            }
        } header: {
            Text("Server")
        }
    }

    private var deviceSection: some View {
        Section {
            LabeledContent("Network") {
                iconValue(monitor.isDeviceOffline ? String(localized: "Offline") : monitor.path.interface.title,
                          monitor.isDeviceOffline ? "wifi.slash" : monitor.path.interface.symbol)
            }
            if monitor.path.interface == .wifi {
                LabeledContent("Wi-Fi Name", value: selector.lastSSID ?? String(localized: "Unavailable"))
            }
            if monitor.path.isExpensive {
                LabeledContent("Metered", value: String(localized: "Yes"))
            }
            if monitor.path.isConstrained {
                LabeledContent("Low Data Mode", value: String(localized: "On"))
            }
            if wifi.canAsk {
                Button("Allow Wi-Fi Name Detection") {
                    Task {
                        await wifi.requestAccess()
                        await selector.select(reason: "settings changed")
                    }
                }
            } else if !wifi.isAllowed {
                Button("Open Location Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        } header: {
            Text("This iPhone")
        } footer: {
            Text(RemoteAccess.shared.pairing != nil
                 ? "iOS shows the Wi-Fi name only with location access, which MediaStorm uses to tell your home network from others. Without it, the home address is still tried and checked before use."
                 : "iOS shows the Wi-Fi name only with location access, which MediaStorm uses to tell your home network from others. Without it, the address in use is kept while on Wi-Fi.")
        }
    }

    private var homeNetworkSection: some View {
        Section {
            if let settings = selector.settings, !settings.homeWifiSSID.isEmpty {
                LabeledContent("Home Wi-Fi", value: settings.homeWifiSSID)
                LabeledContent("Home Address", value: settings.homeURL.map(ServerAddress.display) ?? String(localized: "Not Set"))
                LabeledContent("Away Address", value: settings.remoteURL.map(ServerAddress.display) ?? String(localized: "Not Set"))
                LabeledContent("Set For", value: sourceText(settings.source))
                if let home = selector.isHomeNetwork {
                    LabeledContent("On Home Network", value: home ? String(localized: "Yes") : String(localized: "No"))
                }
            } else {
                Text("Not set up")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Home Network")
        } footer: {
            Text(homeFooter)
        }
    }

    private var remoteSection: some View {
        Section {
            LabeledContent("Remote Access") {
                Text(remoteStatusText)
            }
            if let code = RemoteAccess.shared.pairing?.connectionCode {
                LabeledContent("Paired With", value: String(code.prefix(13)) + "…")
            }
        } header: {
            Text("Remote Access")
        } footer: {
            Text("Remote access stays in use away from home and never falls back to an unverified local address.")
        }
    }

    private var eventsSection: some View {
        Section("Recent Events") {
            if journal.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                DisclosureGroup("\(journal.count) events") {
                    ForEach(Array(journal.prefix(40).enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.event).font(.subheadline.monospaced())
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard)
                                 + (entry.details.map { " · " + $0.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") } ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Picker("Simulate", selection: $fault) {
                Text("Nothing").tag(DebugNetworkFault.Mode.none)
                Text("Device Offline").tag(DebugNetworkFault.Mode.offline)
                Text("Server Unreachable").tag(DebugNetworkFault.Mode.unreachable)
            }
            .onChange(of: fault) { _, mode in connection.simulate(mode) }
        }
    }
    #endif

    /// A value with a leading symbol (a `Label` there lays out at full height in a Form row).
    private func iconValue(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
    }

    // MARK: Text

    private var statusText: String {
        switch connection.status {
        case .online: String(localized: "Connected")
        case .offline: String(localized: "Offline")
        case .reconnecting: String(localized: "Reconnecting")
        }
    }

    private var statusSymbol: String {
        switch connection.status {
        case .online: "checkmark.circle.fill"
        case .offline: "wifi.slash"
        case .reconnecting: "icloud.slash"
        }
    }

    private var routeText: String {
        if session.isHomeDirect { return String(localized: "Home Network") }
        if session.isRemote { return String(localized: "Remote Access") }
        if let settings = selector.settings, settings.isConfigured, let url = session.serverURL {
            if url == settings.homeURL { return String(localized: "Home Address") }
            if url == settings.remoteURL { return String(localized: "Away Address") }
        }
        return String(localized: "Direct")
    }

    private var routeSymbol: String {
        if session.isHomeDirect { return "house" }
        if session.isRemote { return "globe" }
        return "server.rack"
    }

    private var remoteStatusText: String {
        if session.isHomeDirect { return String(localized: "Standing by (on home network)") }
        guard connection.status == .online else { return String(localized: "Reconnecting…") }
        switch irohRoute {
        case .direct: return String(localized: "Connected · Direct")
        case .relay: return String(localized: "Connected · Relay")
        case .detecting: return String(localized: "Connected · Detecting path")
        }
    }

    private var homeFooter: String {
        let base = String(localized: "Set in the web UI under Settings → Server → Network URL Switching.")
        if RemoteAccess.shared.pairing != nil {
            return String(localized: "On the home network the phone talks to your server directly once it confirms the address belongs to the paired server; elsewhere it uses remote access. ") + base
        }
        return String(localized: "On the home Wi-Fi the home address is used, elsewhere the away address. ") + base
    }

    private func sourceText(_ source: MobileNetworkSettings.Source) -> String {
        switch source {
        case .device: String(localized: "This Device")
        case .profile: String(localized: "This Profile")
        case .server: String(localized: "Everyone")
        }
    }

    // MARK: Actions

    private func refreshIrohPath() async {
        guard session.isRemote else { irohRoute = .detecting; return }
        irohRoute = await IrohRoute.current()
    }

    private func checkNow() async {
        checking = true
        checkResult = nil
        await selector.select(reason: "retry")
        let ok = await connection.checkNow()
        await refreshIrohPath()
        journal = MobileReconnectJournal.entries.reversed()
        checkResult = ok ? String(localized: "The server answered.") : String(localized: "The server didn't answer. Retrying automatically.")
        checking = false
    }
}
#endif
