#if os(iOS)
import SwiftUI

/// Settings › Device Name: this device's nickname on the server (`/api/clients/{id}`), which the
/// admin UI's device list and Active Streams show, as the Expo phone app's Device Nickname.
struct MobileDeviceNicknameView: View {
    @Binding var nickname: String?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("e.g. Living Room iPad", text: $text)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(save)
                    .onChange(of: text) { _, value in if value.count > 64 { text = String(value.prefix(64)) } }
            } footer: {
                Text("Give this device a recognizable name for device management. Leave it empty to show the device's own name (\(UIDevice.current.name)).")
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Device Name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(text.trimmingCharacters(in: .whitespaces) == (nickname ?? ""))
                }
            }
        }
        .onAppear {
            text = nickname ?? ""
            focused = true
        }
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saving, value != (nickname ?? "") else { return }
        saving = true
        error = nil
        Task {
            defer { saving = false }
            do {
                nickname = try await APIClient.shared.setDeviceNickname(value)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

extension APIClient {
    private struct ClientRecord: Decodable { let nickname: String? }

    /// This device's nickname on the server; nil when none is set (or the server can't say).
    func deviceNickname() async -> String? {
        let client: ClientRecord? = try? await send("GET", "/api/clients/\(Self.segment(Config.clientID))",
                                                    promptOnLock: false, timeout: 10)
        return client?.nickname.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Sets (or, with an empty name, clears) this device's nickname; returns the saved one. The
    /// device is registered when a profile opens, so this updates its record.
    func setDeviceNickname(_ name: String) async throws -> String? {
        let client: ClientRecord = try await send("PUT", "/api/clients/\(Self.segment(Config.clientID))",
                                                  jsonObject: ["nickname": name])
        return client.nickname.flatMap { $0.isEmpty ? nil : $0 }
    }
}
#endif
