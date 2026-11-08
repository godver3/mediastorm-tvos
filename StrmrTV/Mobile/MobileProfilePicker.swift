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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var height: CGFloat = 0

    /// Up to three avatars a row on a phone (three of 96 pt fit the narrowest, 375 pt), five
    /// on an iPad, the rows centred under a logo that leads the screen.
    private var columns: [GridItem] {
        let perRow = min(max(session.profiles.count, 1), sizeClass == .compact ? 3 : 5)
        return Array(repeating: GridItem(.fixed(96), spacing: 16, alignment: .top), count: perRow)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                BrandMark(height: 150)
                Text("Who's Watching?").font(.title2.weight(.semibold))

                if session.profiles.isEmpty {
                    if let loadError {
                        Text(loadError).foregroundStyle(.red).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await reload() } }
                    } else {
                        ProgressView()
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(session.profiles) { profile in
                            Button { choose(profile) } label: {
                                VStack(spacing: 8) {
                                    ProfileAvatar(profile: profile, size: 72)
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

                    MobileAutoProfileToggle(isOn: $automatic)
                        .onChange(of: automatic) { _, on in if !on { session.setAutoProfile(nil) } }
                }

                if let actionError { Text(actionError).foregroundStyle(.red).multilineTextAlignment(.center) }

                if session.canCancelProfilePick {
                    Button("Cancel") { session.cancelProfilePick() }
                }
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
            // Centred on the screen while it fits, scrolling once it doesn't.
            .frame(minHeight: height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
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
        } catch where !error.isCancellation {
            loadError = error.localizedDescription
        } catch {}
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

/// "Use automatically" as one inset grouped row (Liquid Glass on iOS 26, else the grouped
/// cell fill) with a footnote under it, the way a Settings toggle reads, sized to the
/// avatars rather than spanning the screen.
private struct MobileAutoProfileToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isOn) {
                Label("Use Automatically", systemImage: "person.crop.circle.badge.checkmark")
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .modifier(RowBackground())
            Text("Next time, skip this screen and open the profile you pick.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: 340)
        .padding(.horizontal, 24)
    }

    private struct RowBackground: ViewModifier {
        private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(Color(.secondarySystemGroupedBackground), in: shape)
            }
        }
    }
}
#endif
