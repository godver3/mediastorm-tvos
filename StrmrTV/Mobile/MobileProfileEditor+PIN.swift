#if os(iOS)
import SwiftUI

/// Set or Change PIN: the new PIN twice, on the number pad. 4 to 16 digits, as the PIN pad
/// accepts; the profile then asks for it before it opens.
struct MobileProfilePINView: View {
    let profile: Profile
    var onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var field: Field?
    @StateObject private var parentAuthorization = ParentAuthorizationPrompt()

    private enum Field { case pin, confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New PIN", text: digits($pin))
                        .keyboardType(.numberPad)
                        .focused($field, equals: .pin)
                    SecureField("Confirm PIN", text: digits($confirm))
                        .keyboardType(.numberPad)
                        .focused($field, equals: .confirm)
                } footer: {
                    Text(hint)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(profile.requiresPin ? "Change PIN" : "Set PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save", action: save).disabled(!valid)
                    }
                }
            }
            .interactiveDismissDisabled(saving)
            .parentAuthorizationAlert(parentAuthorization)
            .onAppear { field = .pin }
        }
    }

    private var valid: Bool {
        (PINEntryView.minLength...PINEntryView.maxLength).contains(pin.count) && pin == confirm
    }

    private var hint: String {
        if !confirm.isEmpty, confirm.count >= pin.count, pin != confirm {
            return String(localized: "The PINs don't match.")
        }
        return String(localized: "\(PINEntryView.minLength) to \(PINEntryView.maxLength) digits, for “\(profile.name)”.")
    }

    /// Digits only, at most the longest PIN.
    private func digits(_ binding: Binding<String>) -> Binding<String> {
        Binding(get: { binding.wrappedValue }, set: {
            binding.wrappedValue = String($0.filter(\.isNumber).prefix(PINEntryView.maxLength))
        })
    }

    private func save() {
        guard valid, !saving else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                try await parentAuthorization.run { try await APIClient.shared.setProfilePIN(profile.id, pin, accountPassword: $0) }
                await onSaved()
                dismiss()
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
#endif
