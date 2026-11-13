#if os(iOS)
import SwiftUI

/// The Profiles section, as the Expo phone app's Profiles page: every profile of the account
/// (PIN and Kids marked, the active one checked) to switch to, Create Profile, and the account's
/// stream usage. Beyond Expo's phone page, which sends edits to the web UI, each profile opens
/// an editor (name, colour, kids, PIN, delete) from its info button, swipe or context menu.
struct MobileProfilesView: View {
    @ObservedObject private var session = AppSession.shared
    @State private var pinTarget: Profile?
    @State private var switchingID: String?
    @State private var editing: Profile?
    @State private var deleting: Profile?
    @State private var creating = false
    @State private var usage: APIClient.StreamUsage?
    @State private var message: String?
    @State private var error: String?
    @StateObject private var parentAuthorization = ParentAuthorizationPrompt()

    var body: some View {
        List {
            Section {
                ForEach(session.profiles) { profile in
                    row(profile)
                }
                Button {
                    creating = true
                } label: {
                    Label("Create Profile", systemImage: "plus.circle")
                }
            } footer: {
                Text("Tap a profile to switch who's watching.")
            }

            if let usage {
                Section {
                    LabeledContent {
                        Text("\(usage.currentStreams) of \(usage.maxStreams)")
                    } label: {
                        Label("Streams in Use", systemImage: "play.circle")
                    }
                }
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(.secondary) }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Profiles")
        .refreshable { await reload() }
        .task { await reload() }
        .task(id: session.profile?.id) { await pollUsage() }
        .navigationDestination(item: $editing) { MobileProfileEditor(profile: $0) }
        .sheet(isPresented: $creating) {
            MobileProfileCreateView { created in
                message = String(localized: "Created profile “\(created.name)”.")
            }
        }
        .fullScreenCover(item: $pinTarget) { profile in
            MobilePINEntryView(profile: profile, verify: { await verify(profile, pin: $0) },
                               onCancel: { pinTarget = nil })
        }
        .confirmationDialog(deleting.map { String(localized: "Delete “\($0.name)”?") } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { profile in
            Button("Delete Profile", role: .destructive) { Task { await delete(profile) } }
        } message: { _ in
            Text("Its watch history, watchlist and settings are deleted from the server. This can't be undone.")
        }
        .parentAuthorizationAlert(parentAuthorization)
    }

    private func row(_ profile: Profile) -> some View {
        let active = profile.id == session.profile?.id
        return HStack(spacing: 14) {
            Button { choose(profile) } label: {
                HStack(spacing: 14) {
                    ProfileAvatar(profile: profile, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.name).foregroundStyle(.primary)
                        badges(profile)
                    }
                    Spacer(minLength: 8)
                    if switchingID == profile.id {
                        ProgressView()
                    } else if active {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(profile.name))
            .accessibilityValue(active ? Text("Active") : Text(""))
            .accessibilityHint(active ? Text("") : Text("Switches to this profile"))

            Button { editing = profile } label: {
                Image(systemName: "info.circle").imageScale(.large)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Edit \(profile.name)"))
        }
        .swipeActions(edge: .trailing) {
            if !active {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = profile }
            }
            Button("Edit", systemImage: "pencil") { editing = profile }
        }
        .contextMenu {
            if !active { Button("Switch to Profile", systemImage: "person.crop.circle") { choose(profile) } }
            Button("Edit Profile", systemImage: "pencil") { editing = profile }
            if !active {
                Button("Delete Profile", systemImage: "trash", role: .destructive) { deleting = profile }
            }
        }
    }

    @ViewBuilder
    private func badges(_ profile: Profile) -> some View {
        let active = profile.id == session.profile?.id
        if profile.requiresPin || profile.isKidsProfile == true || active {
            HStack(spacing: 10) {
                if active { Text("Active").foregroundStyle(.tint) }
                if profile.requiresPin { Label("PIN", systemImage: "lock.fill") }
                if profile.isKidsProfile == true { Label("Kids", systemImage: "figure.and.child.holdinghands") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
    }

    private func reload() async {
        do {
            try await session.reloadProfiles()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// The stream count, re-read every 10 seconds while the page shows (as Expo polls it).
    private func pollUsage() async {
        guard let id = session.profile?.id else { return }
        while !Task.isCancelled {
            usage = await APIClient.shared.streamUsage(profileID: id)
            try? await Task.sleep(for: .seconds(10))
        }
    }

    private func choose(_ profile: Profile) {
        guard switchingID == nil, profile.id != session.profile?.id else { return }
        message = nil
        error = nil
        if profile.requiresPin {
            pinTarget = profile
            return
        }
        switchingID = profile.id
        Task {
            defer { switchingID = nil }
            do {
                _ = try await session.select(profile)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func verify(_ profile: Profile, pin: String) async -> PINVerification {
        do {
            guard try await session.select(profile, pin: pin) else { return .wrong }
            pinTarget = nil
            return .unlocked
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func delete(_ profile: Profile) async {
        deleting = nil
        do {
            try await parentAuthorization.run { try await APIClient.shared.deleteProfile(profile.id, accountPassword: $0) }
            message = String(localized: "Deleted profile “\(profile.name)”.")
            await reload()
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
