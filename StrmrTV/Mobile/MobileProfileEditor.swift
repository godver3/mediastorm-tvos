#if os(iOS)
import SwiftUI

/// One profile's settings: name, colour, kids profile, PIN and delete, through the `/api/users`
/// calls the admin UI makes (Expo's phone app sends these to the web UI). Each change saves at
/// once; a profile with a PIN asks for it first when the server enforces PINs.
struct MobileProfileEditor: View {
    @ObservedObject private var session = AppSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profile: Profile
    @State private var name: String
    @State private var kids: Bool
    @State private var customColor: Color
    @State private var working = false
    @State private var error: String?
    @State private var confirmRemovePIN = false
    @State private var confirmDelete = false
    @State private var editingPIN = false
    @StateObject private var parentAuthorization = ParentAuthorizationPrompt()

    init(profile: Profile) {
        _profile = State(initialValue: profile)
        _name = State(initialValue: profile.name)
        _kids = State(initialValue: profile.isKidsProfile == true)
        _customColor = State(initialValue: profile.color.flatMap { Color(hex: $0) } ?? .blue)
    }

    private var isActive: Bool { profile.id == session.profile?.id }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                ProfileAvatar(profile: profile, size: 96)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            Section("Name") {
                TextField("Profile Name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(rename)
                if trimmedName != profile.name, !trimmedName.isEmpty {
                    Button("Save Name", action: rename).disabled(working)
                }
            }

            Section {
                MobileProfileColorGrid(selected: profile.color) { hex in save { try await $0.setProfileColor(profile.id, hex) } }
                ColorPicker("Custom Colour", selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, color in
                        guard let hex = color.hexString, hex.caseInsensitiveCompare(profile.color ?? "") != .orderedSame else { return }
                        save { try await $0.setProfileColor(profile.id, hex) }
                    }
            } header: {
                Text("Colour")
            } footer: {
                Text("The avatar's colour where the profile has no picture.")
            }

            Section {
                Toggle("Kids Profile", isOn: $kids)
                    .onChange(of: kids) { _, on in
                        guard on != (profile.isKidsProfile == true) else { return }
                        save { api in try await parentAuthorization.run { try await api.setKidsProfile(profile.id, on, accountPassword: $0) } }
                    }
            } footer: {
                Text("Kids profiles see only titles their content rating or allowed lists permit, and no Live TV. Ratings and lists are set in the server's web UI.")
            }

            Section {
                if profile.requiresPin {
                    Button("Change PIN") { editingPIN = true }
                    Button("Remove PIN", role: .destructive) { confirmRemovePIN = true }
                        .confirmationDialog("Remove the PIN from “\(profile.name)”?", isPresented: $confirmRemovePIN,
                                            titleVisibility: .visible) {
                            Button("Remove PIN", role: .destructive) {
                                save { api in try await parentAuthorization.run { try await api.clearProfilePIN(profile.id, accountPassword: $0) } }
                            }
                        } message: {
                            Text("Anyone using this device will be able to open the profile.")
                        }
                } else {
                    Button("Set PIN") { editingPIN = true }
                }
            } header: {
                Text("PIN")
            } footer: {
                Text(profile.requiresPin ? "This profile asks for its PIN before it opens." : "A PIN keeps others from opening this profile.")
            }

            if !isActive {
                Section {
                    Button("Delete Profile", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete “\(profile.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete Profile", role: .destructive) { delete() }
                        } message: {
                            Text("Its watch history, watchlist and settings are deleted from the server. This can't be undone.")
                        }
                } footer: {
                    Text("Switch to another profile to delete the one in use.")
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .overlay { if working { ProgressView() } }
        .parentAuthorizationAlert(parentAuthorization)
        .sheet(isPresented: $editingPIN) {
            MobileProfilePINView(profile: profile) { await refresh() }
        }
    }

    private func rename() {
        guard !trimmedName.isEmpty, trimmedName != profile.name else { return }
        let value = trimmedName
        save { try await $0.renameProfile(profile.id, to: value) }
    }

    /// Runs one edit, then reads the profile back; on failure the form returns to the server's values.
    private func save<T>(_ edit: @escaping @MainActor (APIClient) async throws -> T) {
        guard !working else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                _ = try await edit(APIClient.shared)
            } catch is CancellationError {
                // The account password prompt was cancelled; the refresh restores the form.
            } catch {
                self.error = error.localizedDescription
            }
            await refresh()
        }
    }

    private func refresh() async {
        try? await session.reloadProfiles()
        guard let fresh = session.profiles.first(where: { $0.id == profile.id }) else { return }
        profile = fresh
        name = fresh.name
        kids = fresh.isKidsProfile == true
    }

    private func delete() {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await parentAuthorization.run { try await APIClient.shared.deleteProfile(profile.id, accountPassword: $0) }
                try? await session.reloadProfiles()
                dismiss()
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// A row of preset avatar colours, the current one ringed.
private struct MobileProfileColorGrid: View {
    let selected: String?
    let pick: (String) -> Void

    static let palette = ["#3B82F6", "#8B5CF6", "#EC4899", "#EF4444", "#F97316", "#EAB308",
                          "#22C55E", "#14B8A6", "#06B6D4", "#6366F1", "#78716C", "#64748B"]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
            ForEach(Self.palette, id: \.self) { hex in
                let isSelected = hex.caseInsensitiveCompare(selected ?? "") == .orderedSame
                Button { pick(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 36, height: 36)
                        .padding(3)
                        .overlay(Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(hex))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

extension Color {
    /// `#RRGGBB`, for the server's profile colour.
    var hexString: String? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
#endif
