#if os(iOS)
import SwiftUI

/// Settings on the phone, in the Expo phone app's order: the profile, this device (name,
/// downloads), the device's playback and display choices as drill-downs, Live TV recovery,
/// Server, Account and About. Each page writes the same stores as the TV's Settings.
struct MobileSettingsView: View {
    @ObservedObject private var session = AppSession.shared
    @State private var confirmingSignOut = false
    @State private var nickname: String?
    @State private var reloading = false
    @State private var liveResetResult: String?

    var body: some View {
        List {
            if let profile = session.profile {
                Section {
                    HStack(spacing: 14) {
                        ProfileAvatar(profile: profile, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.headline)
                            if let host = session.serverURL?.host() {
                                Text(host).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    Button("Switch Profile") { Task { await session.switchProfile() } }
                }
            }

            Section {
                NavigationLink {
                    MobileDeviceNicknameView(nickname: $nickname)
                } label: {
                    LabeledContent {
                        Text(nickname ?? String(localized: "Not Set"))
                    } label: {
                        Label("Device Name", systemImage: "iphone")
                    }
                }
                NavigationLink {
                    MobileDownloadSettingsView()
                } label: {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            } header: {
                Text("This Device")
            }

            Section {
                NavigationLink {
                    MobilePlaybackSettingsView()
                } label: {
                    Label("Playback", systemImage: "play.rectangle")
                }
                NavigationLink {
                    MobileSubtitleStyleView()
                } label: {
                    Label("Subtitle Style", systemImage: "captions.bubble")
                }
                NavigationLink {
                    MobileHomeRowsSettingsView()
                } label: {
                    Label("Home Rows", systemImage: "rectangle.grid.1x2")
                }
                NavigationLink {
                    MobileMenuSettingsView()
                } label: {
                    Label("Tabs", systemImage: "dock.rectangle")
                }
                NavigationLink {
                    MobileCardSettingsView()
                } label: {
                    Label("Cards & Spoilers", systemImage: "rectangle.on.rectangle")
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("Stored on this device. Choices left at Default follow the server's settings for this profile.")
            }

            Section {
                Button {
                    liveResetResult = Self.liveResetText(LiveHLSPreference.resetAll())
                } label: {
                    LabeledContent("Try Direct Again") { Text(liveResetResult ?? "") }
                }
            } header: {
                Text("Live TV Playback Recovery")
            } footer: {
                Text("After a successful HLS recovery, this device remembers HLS for that source. Reset them to try Direct again; your source settings stay unchanged.")
            }

            MobileServerSection()

            Section("Account") {
                LabeledContent("Signed In As", value: session.username ?? "—")
                Button {
                    Task { await reload() }
                } label: {
                    LabeledContent("Reload Settings") { Text(reloading ? String(localized: "Reloading…") : "") }
                }
                .disabled(reloading)
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }
                    .confirmationDialog("Sign out of \(session.username ?? String(localized: "this account"))?",
                                        isPresented: $confirmingSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
                    }
            }

            MobileAboutSection()
        }
        .navigationTitle("Settings")
        .task { nickname = await APIClient.shared.deviceNickname() }
        .task { await TrackSettingsStore.shared.refresh() }
        .task { await SpoilerSettingsStore.shared.refresh() }
    }

    /// Expo's Reload: reads the profile's and this device's server settings again.
    private func reload() async {
        reloading = true
        defer { reloading = false }
        async let tracks: Void = TrackSettingsStore.shared.refresh()
        async let spoilers: Void = SpoilerSettingsStore.shared.refresh()
        async let badges: Void = BadgeSettingsStore.shared.refresh()
        async let subtitles: Void = PlaybackCoordinator.shared.refreshSubtitleStyle()
        async let name = APIClient.shared.deviceNickname()
        _ = await (tracks, spoilers, badges, subtitles)
        nickname = await name
    }

    private static func liveResetText(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Nothing to reset")
        case 1: String(localized: "Reset 1 source")
        default: String(localized: "Reset \(count) sources")
        }
    }
}
#endif
