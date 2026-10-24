import SwiftUI

/// Server, profile, account and about.
struct SettingsView: View {
    @ObservedObject private var session = AppSession.shared
    @ObservedObject private var logs = LogUploader.shared
    @ObservedObject private var trailers = TrailerSettingsStore.shared
    @State private var status: ConnectionStatus = .checking
    @State private var confirmSignOut = false
    @State private var confirmChangeServer = false

    enum ConnectionStatus: Equatable {
        case checking, connected, unreachable(String)
    }

    var body: some View {
        // The tvOS Settings layout: artwork on the left, the grouped list on the right.
        HStack(alignment: .center, spacing: 60) {
            VStack(spacing: 30) {
                BrandMark(height: 260, tile: true)
                if let name = session.profile?.name {
                    Text(name).font(.headline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            form
                .frame(width: 1040)
                // The list's clip starts below the tab bar, so rows never scroll under it.
                .padding(.top, HomeView.tabBarClearance)
        }
        // Title-safe margins; the list's own margins hold the focus lift.
        .padding(.horizontal, 30)
        .task { await checkConnection() }
        .task { await trailers.refresh() }
        .task { await TrackSettingsStore.shared.refresh() }
        .task { await SpoilerSettingsStore.shared.refresh() }
        .confirmationDialog("Sign out of \(session.username ?? "this account")?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Change server?", isPresented: $confirmChangeServer) {
            Button("Change Server") { session.changeServer() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll sign in again on the new server.")
        }
    }

    private var form: some View {
        Form {
            Section("Server") {
                SettingsRow(title: "Address", value: session.isRemote
                    ? String(localized: "Remote access (iroh)")
                    : session.serverURL.map(ServerAddress.display) ?? "—")
                SettingsRow(title: "Status", value: statusText, systemImage: statusSymbol)
                Button("Check Connection") { Task { await checkConnection() } }
                    .accessibilityHint(Text("Checks that the server is reachable"))
                SpeedTestRows()
                Button("Change Server…") { confirmChangeServer = true }
                    .accessibilityHint(Text("Signs out and connects to a different server"))
            }

            Section("Profile") {
                if let profile = session.profile {
                    HStack(spacing: 30) {
                        ProfileAvatar(profile: profile, size: 60)
                        Text(profile.name)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Current profile: \(profile.name)"))
                }
                Button("Switch Profile") { Task { await session.switchProfile() } }
            }

            Section("Home") {
                NavigationLink("Home Layout") { HomeLayoutSettingsView() }
                NavigationLink("Menu") { MenuSettingsView() }
            }

            Section("Playback") {
                NavigationLink("Subtitle Style") { SubtitleSettingsView() }
                ChoiceRow(title: "Auto-play Trailers", selection: $trailers.autoPlayOverride,
                          defaultValue: trailers.serverAutoPlay ?? false, choices: [
                              .init(value: true, name: String(localized: "On")),
                              .init(value: false, name: String(localized: "Off")),
                          ])
                    .accessibilityHint(Text("Plays a title's trailer behind its details page"))
                TrackSettingsRows()
                AtmosSettingsRows()
                LiveHLSResetRow()
            }

            Section("Spoilers") {
                SpoilerSettingsRows()
            }

            Section("Account") {
                SettingsRow(title: "Signed In As", value: session.username ?? "—")
                Button("Sign Out") { confirmSignOut = true }
            }

            Section("About") {
                SettingsRow(title: "Version", value: "\(Config.appVersion) (\(Config.buildNumber))")
                SettingsRow(title: "Server Version", value: serverVersionText)
                SettingsRow(title: "Device ID", value: Config.clientID)
                Button {
                    Task { await logs.uploadNow() }
                } label: {
                    LabeledContent("Upload Logs") { Text(logStatusText) }
                }
                .disabled(logs.status == .uploading)
                .accessibilityHint(Text("Sends this device's log to the server for a bug report"))
            }
        }
        // Room inside the list for the focused row's lift and shadow, so a focused row is
        // never cut off. The list keeps its clip: rows must not draw over the tab bar.
        .settingsListMargins(50)
    }

    private var statusText: String {
        switch status {
        case .checking: String(localized: "Checking…")
        case .connected: String(localized: "Connected")
        case let .unreachable(message): message
        }
    }

    private var statusSymbol: String? {
        switch status {
        case .checking: nil
        case .connected: "checkmark.circle.fill"
        case .unreachable: "exclamationmark.triangle.fill"
        }
    }

    private var logStatusText: String {
        switch logs.status {
        case .idle: ""
        case .uploading: String(localized: "Uploading…")
        case let .uploaded(date): String(localized: "Sent \(date.formatted(date: .omitted, time: .shortened))")
        case let .failed(message): message
        }
    }

    private var serverVersionText: String {
        guard let v = session.serverVersion else { return "—" }
        if let build = v.buildId, !build.isEmpty { return "\(v.version) (\(build))" }
        return v.version
    }

    private func checkConnection() async {
        guard let url = session.serverURL else { return }
        status = .checking
        do {
            try await APIClient.shared.checkHealth(of: url)
            status = .connected
        } catch {
            status = .unreachable(error.localizedDescription)
        }
    }
}

/// Read-only label / value row. Focusable so it scrolls into view with the remote
/// and VoiceOver reads it.
private struct SettingsRow: View {
    let title: LocalizedStringKey
    let value: String
    var systemImage: String?

    var body: some View {
        Button {} label: {
            LabeledContent(title) {
                HStack(spacing: 12) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(value).lineLimit(2)
                }
            }
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }
}
