#if os(iOS)
import SwiftUI

/// The phone's Connect to Your Server screen: `ServerConnectView`'s state and actions in a
/// native inset grouped form (real text field rows, and the form keeps the focused field
/// above the keyboard). The TV keeps its own centred layout.
struct MobileServerForm: View {
    @Binding var address: String
    @Binding var code: String
    let servers: [DiscoveredServer]
    let resolved: URL?
    let error: String?
    let isConnecting: Bool
    let connectingServerID: String?
    let isPairing: Bool
    let canCancel: Bool
    let connect: () -> Void
    let connectTo: (DiscoveredServer) -> Void
    let pair: () -> Void
    let cancel: () -> Void

    private enum Field { case address, code }
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MobileBrandHeader()
                }
                .listRowBackground(Color.clear)

                if !servers.isEmpty {
                    Section("On Your Network") {
                        ForEach(servers) { server in
                            Button { connectTo(server) } label: {
                                HStack(spacing: 12) {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(server.name).foregroundStyle(.primary)
                                            if let version = server.version {
                                                Text("MediaStorm \(version)").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    } icon: {
                                        Image(systemName: "server.rack")
                                    }
                                    Spacer(minLength: 0)
                                    if connectingServerID == server.id { ProgressView() }
                                }
                            }
                            .disabled(isConnecting || isPairing)
                            .accessibilityHint(Text("Connects to this server"))
                        }
                    }
                }

                Section {
                    TextField("Server Address", text: $address, prompt: Text(verbatim: "192.168.1.10 or media.example.com"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focus, equals: .address)
                        .onSubmit(connect)
                    MobileBusyRow(title: "Connect", isBusy: isConnecting, action: connect)
                        .disabled(resolved == nil || isPairing)
                } header: {
                    Text("Server Address")
                } footer: {
                    if let resolved {
                        Text("Connects to \(resolved.absoluteString)")
                    } else {
                        Text("Local addresses use port \(String(ServerAddress.defaultPort)) unless you add one.")
                    }
                }

                Section {
                    TextField("Connection Code", text: $code, prompt: Text(verbatim: "mshost-ABC123-DEF456-GHJ789"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focus, equals: .code)
                        .onSubmit(pair)
                    MobileBusyRow(title: "Connect with Code", isBusy: isPairing, action: pair)
                        .disabled(RemoteAccess.normalize(code) == nil || isConnecting)
                } header: {
                    Text("Away From Home")
                } footer: {
                    Text("Get a connection code from Remote Access in your server's admin settings.")
                }

                if let error {
                    Section { MobileFormError(message: error) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // The bundled logo sits on its own dark backing; the form matches it.
            .scrollContentBackground(.hidden)
            .background(Color.brandBackground)
            .navigationTitle("Connect to Your Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel).disabled(isConnecting || isPairing)
                    }
                }
            }
        }
    }
}

/// The phone's Sign In screen, `LoginView`'s state and actions in a native form.
struct MobileLoginForm: View {
    @Binding var username: String
    @Binding var password: String
    let server: Text?
    let notice: String?
    let error: String?
    let isSigningIn: Bool
    let signIn: () -> Void
    let changeServer: () -> Void

    private enum Field { case username, password }
    @FocusState private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MobileBrandHeader()
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .username)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit(signIn)
                } header: {
                    Text("Account")
                } footer: {
                    if let notice, error == nil { Text(notice) } else if let server { server }
                }

                Section {
                    MobileBusyRow(title: "Sign In", isBusy: isSigningIn, action: signIn)
                        .disabled(username.isEmpty || password.isEmpty)
                }

                if let error {
                    Section { MobileFormError(message: error) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // The bundled logo sits on its own dark backing; the form matches it.
            .scrollContentBackground(.hidden)
            .background(Color.brandBackground)
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Change Server", action: changeServer).disabled(isSigningIn)
                }
            }
        }
    }
}

/// The brand logo centred above a form.
private struct MobileBrandHeader: View {
    var body: some View {
        BrandMark(height: 110)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A form row's action that shows a spinner in place of its title while busy.
private struct MobileBusyRow: View {
    let title: LocalizedStringKey
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isBusy { ProgressView() }
            }
        }
        .disabled(isBusy)
    }
}

private struct MobileFormError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .accessibilityLabel(Text("Error: \(message)"))
    }
}
#endif
