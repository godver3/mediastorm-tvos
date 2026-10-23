import SwiftUI

/// "Who's watching?" grid, with a PIN prompt for protected profiles.
struct ProfilePickerView: View {
    @ObservedObject private var session = AppSession.shared
    @State private var pinTarget: Profile?
    @State private var busyID: String?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var automatic = AppSession.shared.autoProfileID != nil
    @FocusState private var focusedID: String?
    /// The profile Up returns to from the tickbox (geometry alone picks the nearest one).
    @State private var lastProfileFocus: String?
    private static let checkboxFocus = "auto-select"

    var body: some View {
        VStack(spacing: 56) {
            VStack(spacing: 30) {
                BrandMark(height: 250)
                Text("Who's Watching?").font(.title3.weight(.semibold))
            }

            if session.profiles.isEmpty {
                if let loadError {
                    OnboardingError(message: loadError)
                    Button("Try Again") { Task { await reload() } }
                } else {
                    ProgressView()
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 60) {
                        ForEach(session.profiles) { profile in
                            ProfileButton(profile: profile, isBusy: busyID == profile.id) { choose(profile) }
                                .focused($focusedID, equals: profile.id)
                                .disabled(isParked(profile))
                        }
                    }
                    .padding(60)
                }
                .scrollClipDisabled()
                .fixedSize(horizontal: true, vertical: false)
                .focusSection()

                // Full-width section so Down reaches it from any profile, not just the one above it.
                AutoSelectCheckbox(isOn: $automatic)
                    .focused($focusedID, equals: Self.checkboxFocus)
                    .frame(maxWidth: .infinity)
                    .focusSection()
            }

            if let actionError { OnboardingError(message: actionError) }

            if session.canCancelProfilePick {
                Button("Cancel") { session.cancelProfilePick() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focusedID, initialFocusID)
        .onChange(of: focusedID) { _, id in
            if let id, id != Self.checkboxFocus { lastProfileFocus = id }
        }
        .onExitCommand { session.cancelProfilePick() }
        .task { if session.profiles.isEmpty { await reload() } }
        .fullScreenCover(item: $pinTarget) { profile in
            PINEntryView(
                profile: profile,
                verify: { await verify(profile, pin: $0) },
                onCancel: { pinTarget = nil }
            )
        }
    }

    /// While the tickbox has focus only the profile Down left from is focusable, so Up
    /// returns there rather than to the nearest one (setting focus on the move races
    /// the focus engine).
    private func isParked(_ profile: Profile) -> Bool {
        guard focusedID == Self.checkboxFocus, let lastProfileFocus else { return false }
        return profile.id != lastProfileFocus
    }

    /// Current or last profile; in debug builds, the `Secrets` profile on a fresh start.
    private var initialFocusID: String? {
        if let id = session.profile?.id ?? session.lastProfileID { return id }
        #if DEBUG
        if let s = DebugPrefill.secrets { return session.profiles.first { $0.name == s.profileName }?.id }
        #endif
        return nil
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

/// "Use this profile automatically": the next pick opens at launch. Unticking forgets
/// the current one straight away, so Settings → Switch Profile → Cancel turns it off.
private struct AutoSelectCheckbox: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            if !isOn { AppSession.shared.setAutoProfile(nil) }
        } label: {
            Label("Use this profile automatically", systemImage: isOn ? "checkmark.square.fill" : "square")
                .font(.callout)
        }
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

private struct ProfileButton: View {
    let profile: Profile
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 24) {
                ProfileAvatar(profile: profile, size: 180)
                    .overlay { if isBusy { ProgressView() } }
                Text(profile.requiresPin ? "\(profile.name) \(Image(systemName: "lock.fill"))" : "\(profile.name)")
            }
        }
        .buttonStyle(AvatarLiftButtonStyle())
        .accessibilityLabel(Text(profile.name))
        .accessibilityHint(profile.requiresPin ? Text("Requires a PIN") : Text(""))
    }
}

/// The system lift (scale + shadow) applied to a round avatar: `.borderless` lifts a
/// rectangular platter or the lock symbol, `.plain` adds a card behind the whole label.
private struct AvatarLiftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Lift(configuration: configuration)
    }

    private struct Lift: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? .primary : .secondary)
                .scaleEffect(configuration.isPressed ? 1.02 : isFocused ? 1.12 : 1)
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 24, y: 18)
                .animation(.easeOut(duration: 0.18), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}
