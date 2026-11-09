#if os(iOS)
import SwiftUI

/// Cast To: the Chromecasts and DLNA TVs on the network in one list (the Expo app's two
/// pickers), the cast that is running with Stop Casting, and a renderer added by its address.
struct CastDevicePicker: View {
    @ObservedObject private var cast = CastController.shared
    let onPick: (CastDevice) -> Void
    let onShowRemote: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var adding = false
    @State private var addError: String?

    var body: some View {
        NavigationStack {
            List {
                activeSection
                deviceSection(String(localized: "Chromecast"), devices: cast.chromecasts,
                              empty: String(localized: "No Chromecasts found. They must be on the same Wi-Fi network as this device."))
                deviceSection(String(localized: "DLNA TVs"), devices: cast.renderers,
                              empty: cast.isSearching ? nil : String(localized: "No DLNA TVs found. Add one by its address below."),
                              searching: cast.isSearching)
                manualSection
            }
            .navigationTitle("Cast To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { cast.refreshRenderers() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(cast.isSearching)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { cast.startDiscovery() }
        .onDisappear { cast.stopDiscovery() }
        .accessibilityIdentifier("cast.picker")
    }

    @ViewBuilder
    private var activeSection: some View {
        if let session = cast.session, session.phase == .active {
            Section("Now Casting") {
                Button(action: onShowRemote) {
                    HStack(spacing: 12) {
                        Image.castIcon().foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title).foregroundStyle(.primary)
                            Text("Playing on \(session.device.name)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                Button("Stop Casting", role: .destructive) { cast.stop() }
            }
        }
    }

    private func deviceSection(_ title: String, devices: [CastDevice], empty: String?, searching: Bool = false) -> some View {
        Section {
            ForEach(devices) { device in
                Button { onPick(device) } label: { DeviceRow(device: device, current: cast.session?.device.id == device.id) }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("cast.device.\(device.name)")
            }
            if devices.isEmpty, let empty {
                Text(empty).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 6) {
                Text(title)
                if searching { ProgressView().controlSize(.mini) }
            }
        }
    }

    private var manualSection: some View {
        Section {
            HStack {
                TextField("192.168.1.42", text: $address)
                    .keyboardType(.decimalPad)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(add)
                if adding {
                    ProgressView()
                } else {
                    Button("Add", action: add).disabled(address.castTrimmed.isEmpty)
                }
            }
            if let addError {
                Text(addError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Add by Address")
        } footer: {
            Text("For a DLNA TV that isn't listed, enter its IP address on your network.")
        }
    }

    private func add() {
        let host = address.castTrimmed
        guard !host.isEmpty, !adding else { return }
        adding = true
        addError = nil
        Task {
            do {
                let device = try await cast.addRenderer(host: host)
                address = ""
                adding = false
                onPick(device)
            } catch {
                addError = error.localizedDescription
                adding = false
            }
        }
    }
}

private struct DeviceRow: View {
    let device: CastDevice
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind == .googleCast ? "tv.and.mediabox" : "tv")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).foregroundStyle(.primary)
                Text([device.detail, device.address].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if current { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
        .contentShape(Rectangle())
    }
}
#endif
