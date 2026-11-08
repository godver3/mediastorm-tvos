#if os(iOS)
import SwiftUI

/// Create Profile, as the Expo phone app's: the account password confirms it's the account's
/// owner (checked first, as Expo does), then the new profile's name.
struct MobileProfileCreateView: View {
    var onCreated: (Profile) -> Void
    @ObservedObject private var session = AppSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var name = ""
    @State private var working = false
    @State private var error: String?
    @FocusState private var field: Field?

    private enum Field { case password, name }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Account", value: session.username ?? "—")
                    SecureField("Account Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.next)
                        .focused($field, equals: .password)
                        .onSubmit { field = .name }
                } header: {
                    Text("Confirm Account Password")
                } footer: {
                    Text("Verify your account before creating a new profile.")
                }
                Section {
                    TextField("Profile Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($field, equals: .name)
                        .onSubmit(create)
                } header: {
                    Text("Name")
                } footer: {
                    Text("The name that shows for this profile. Set its colour, PIN or kids mode after it's created.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Create", action: create).disabled(!canCreate)
                    }
                }
            }
            .interactiveDismissDisabled(working)
            .onAppear { field = .password }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !password.isEmpty && !trimmedName.isEmpty }

    private func create() {
        guard canCreate, !working else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                guard try await APIClient.shared.verifyAccountPassword(password) else {
                    password = ""
                    field = .password
                    error = String(localized: "The account password is incorrect.")
                    return
                }
                let created = try await APIClient.shared.createProfile(name: trimmedName, password: password)
                try? await session.reloadProfiles()
                onCreated(created)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
#endif
