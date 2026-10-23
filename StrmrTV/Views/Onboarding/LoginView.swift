import SwiftUI

/// Username / password sign-in against the chosen server.
struct LoginView: View {
    @ObservedObject private var session = AppSession.shared
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isSigningIn = false

    var body: some View {
        OnboardingLayout(
            title: "Sign In",
            subtitle: session.isRemote ? Text("Remote access")
                : session.serverURL.map { Text(verbatim: ServerAddress.display($0)) }
        ) {
            if let notice = session.loginNotice, error == nil {
                Text(notice).foregroundStyle(.secondary)
            }

            TextField("Username", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("Username"))
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(signIn)
                .accessibilityLabel(Text("Password"))

            if let error { OnboardingError(message: error) }

            HStack(spacing: 40) {
                BusyButton(title: "Sign In", isBusy: isSigningIn, action: signIn)
                    .disabled(username.isEmpty || password.isEmpty)
                Button("Change Server") { session.changeServer() }
                    .disabled(isSigningIn)
            }
        }
        .onAppear(perform: prefill)
    }

    private func prefill() {
        #if DEBUG
        if username.isEmpty, password.isEmpty, let s = DebugPrefill.secrets {
            username = s.username
            password = s.password
        }
        #endif
    }

    private func signIn() {
        guard !isSigningIn, !username.isEmpty, !password.isEmpty else { return }
        isSigningIn = true
        error = nil
        Task {
            defer { isSigningIn = false }
            do {
                try await session.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password)
                password = ""
            } catch let apiError as APIError where apiError.isDefaultPassword {
                error = String(localized: "This admin account still uses the default password. Change it in the web UI, then sign in here.")
            } catch let apiError as APIError where apiError.isRateLimited {
                error = apiError.localizedDescription  // includes Retry-After
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
