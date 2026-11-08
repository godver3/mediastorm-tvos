#if os(iOS)
import SwiftUI

/// Settings: the current profile with Switch Profile and Sign Out. The rest of the TV's
/// settings sections come over as they are ported.
struct MobileSettingsView: View {
    @ObservedObject private var session = AppSession.shared
    @State private var confirmingSignOut = false

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
                }
            }
            Section {
                Button("Switch Profile") { Task { await session.switchProfile() } }
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }
            }
            Section {
                LabeledContent("Version", value: Config.fullVersion)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out of this server?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
        }
    }
}
#endif
