#if os(iOS)
import SwiftUI

/// "Who's watching?" as a grid of tappable avatars, with the phone PIN pad for protected
/// profiles. Same session calls as the TV's `ProfilePickerView`.
struct MobileProfilePicker: View {
    @ObservedObject private var session = AppSession.shared
    @State private var pinTarget: Profile?
    @State private var busyID: String?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var automatic = AppSession.shared.autoProfileID != nil

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 24)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                BrandMark(height: 72)
                    .padding(.top, 40)
                Text("Who's Watching?").font(.title2.weight(.semibold))

                if session.profiles.isEmpty {
                    if let loadError {
                        Text(loadError).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await reload() } }
                    } else {
                        ProgressView()
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(session.profiles) { profile in
                            Button { choose(profile) } label: {
                                VStack(spacing: 10) {
                                    ProfileAvatar(profile: profile, size: 96)
                                        .overlay { if busyID == profile.id { ProgressView() } }
                                    HStack(spacing: 4) {
                                        Text(profile.name).lineLimit(1)
                                        if profile.requiresPin { Image(systemName: "lock.fill").font(.caption) }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(profile.name))
                            .accessibilityHint(profile.requiresPin ? Text("Requires a PIN") : Text(""))
                        }
                    }
                    .padding(.horizontal, 24)

                    Toggle("Use this profile automatically", isOn: $automatic)
                        .font(.subheadline)
                        .padding(.horizontal, 32)
                        .onChange(of: automatic) { _, on in if !on { session.setAutoProfile(nil) } }
                }

                if let actionError { Text(actionError).foregroundStyle(.red).multilineTextAlignment(.center) }

                if session.canCancelProfilePick {
                    Button("Cancel") { session.cancelProfilePick() }
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .task { if session.profiles.isEmpty { await reload() } }
        .fullScreenCover(item: $pinTarget) { profile in
            MobilePINEntryView(
                profile: profile,
                verify: { await verify(profile, pin: $0) },
                onCancel: { pinTarget = nil }
            )
        }
    }

    private func reload() async {
        loadError = nil
        do {
            try await session.loadProfiles()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func choose(_ profile: Profile) {
        guard busyID == nil else { return }
        actionError = nil
        if profile.requiresPin {
            pinTarget = profile
            return
        }
        busyID = profile.id
        Task {
            defer { busyID = nil }
            do {
                _ = try await session.select(profile, automatic: automatic)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func verify(_ profile: Profile, pin: String) async -> PINVerification {
        do {
            guard try await session.select(profile, pin: pin, automatic: automatic) else { return .wrong }
            pinTarget = nil
            return .unlocked
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
#endif
