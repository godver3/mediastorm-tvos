import SwiftUI

/// First run (and Settings → Change Server): pick a server found on the LAN, or type
/// the backend address; either is checked before moving on.
struct ServerConnectView: View {
    @ObservedObject private var session = AppSession.shared
    @StateObject private var browser = ServerBrowser()
    @State private var address = ""
    @State private var error: String?
    @State private var isConnecting = false
    @State private var connectingServerID: String?
    @State private var code = ""
    @State private var isPairing = false

    private var resolved: URL? { ServerAddress.normalize(address) }

    var body: some View {
        OnboardingLayout(
            title: "Connect to Your Server",
            subtitle: Text("Enter the address of your MediaStorm server. Local addresses use port \(String(ServerAddress.defaultPort)) unless you add one.")
        ) {
            if !browser.servers.isEmpty {
                DiscoveredServerList(servers: browser.servers, busyID: connectingServerID, action: connect(to:))
                    .disabled(isConnecting)
            }

            TextField("Server Address", text: $address, prompt: Text(verbatim: "192.168.1.10 or media.example.com"))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(connect)
                .accessibilityLabel(Text("Server address"))

            if let resolved {
                Text("Connects to \(resolved.absoluteString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let error { OnboardingError(message: error) }

            HStack(spacing: 40) {
                BusyButton(title: "Connect", isBusy: isConnecting, action: connect)
                    .disabled(resolved == nil || isPairing)
                if session.canCancelServerChange {
                    Button("Cancel") { session.cancelServerChange() }
                        .disabled(isConnecting || isPairing)
                }
            }

            // Away from home: the server's admin UI (Remote Access) issues a connection code.
            VStack(alignment: .leading, spacing: 20) {
                Text("Away From Home")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                TextField("Connection Code", text: $code, prompt: Text(verbatim: "mshost-ABC123-DEF456-GHJ789"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(pair)
                    .accessibilityLabel(Text("Connection code"))
                BusyButton(title: "Connect with Code", isBusy: isPairing, action: pair)
                    .disabled(RemoteAccess.normalize(code) == nil || isConnecting)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
        }
        .onAppear {
            prefill()
            browser.start()
        }
        .onDisappear { browser.stop() }
        .onChange(of: address) { error = nil }
        .onChange(of: code) { error = nil }
        .animation(.default, value: browser.servers)
    }

    private func prefill() {
        guard address.isEmpty else { return }
        if let current = session.serverURL {
            address = ServerAddress.display(current)
            return
        }
        #if DEBUG
        if let s = DebugPrefill.secrets { address = s.serverURL }
        #endif
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        error = nil
        Task {
            defer { isConnecting = false }
            do {
                try await session.connect(to: address)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func pair() {
        guard !isPairing, !isConnecting else { return }
        isPairing = true
        error = nil
        Task {
            defer { isPairing = false }
            do {
                try await session.connect(code: code)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func connect(to server: DiscoveredServer) {
        guard !isConnecting else { return }
        isConnecting = true
        connectingServerID = server.id
        error = nil
        Task {
            defer {
                isConnecting = false
                connectingServerID = nil
            }
            do {
                try await session.connect(to: server)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// Servers advertising `_mediastorm._tcp` on this network.
private struct DiscoveredServerList: View {
    let servers: [DiscoveredServer]
    let busyID: String?
    let action: (DiscoveredServer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("On Your Network")
                .font(.headline)
                .foregroundStyle(.secondary)
            ForEach(servers) { server in
                Button { action(server) } label: {
                    HStack(spacing: 24) {
                        Image(systemName: "server.rack")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.name)
                            if let version = server.version {
                                Text("MediaStorm \(version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if busyID == server.id { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel(Text(server.name))
                .accessibilityHint(Text("Connects to this server"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
