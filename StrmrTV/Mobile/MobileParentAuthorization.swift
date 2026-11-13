#if os(iOS)
import SwiftUI

/// Account-password confirmation for the changes the server guards as parental controls (kids
/// profile, PINs, deleting a profile). The change runs without a password first; when the server
/// answers `parent_authorization_required` this asks for the account password and retries with
/// it, asking again after a wrong one. The password is used for that one change and not kept.
@MainActor
final class ParentAuthorizationPrompt: ObservableObject {
    @Published var isPresented = false
    @Published var password = ""
    @Published private(set) var message: String?
    private var pending: CheckedContinuation<String?, Never>?

    /// Throws `CancellationError` when the user cancels the prompt.
    func run<T>(_ change: (_ accountPassword: String?) async throws -> T) async throws -> T {
        var password: String?
        while true {
            do {
                return try await change(password)
            } catch let error as APIError where error.code == APIError.Code.parentAuthorizationRequired {
                let message = password == nil ? nil : String(localized: "That isn't the account's password.")
                guard let entered = await ask(message) else { throw CancellationError() }
                password = entered
            }
        }
    }

    func confirm() { finish(password.isEmpty ? nil : password) }
    func cancel() { finish(nil) }

    private func ask(_ message: String?) async -> String? {
        finish(nil)
        self.message = message
        password = ""
        isPresented = true
        return await withCheckedContinuation { pending = $0 }
    }

    private func finish(_ value: String?) {
        password = ""
        isPresented = false
        let continuation = pending
        pending = nil
        continuation?.resume(returning: value)
    }
}

extension View {
    /// Shows `prompt`'s password alert over this view.
    func parentAuthorizationAlert(_ prompt: ParentAuthorizationPrompt) -> some View {
        modifier(ParentAuthorizationAlert(prompt: prompt))
    }
}

private struct ParentAuthorizationAlert: ViewModifier {
    @ObservedObject var prompt: ParentAuthorizationPrompt

    func body(content: Content) -> some View {
        content
            .alert("Account Password", isPresented: $prompt.isPresented) {
                SecureField("Password", text: $prompt.password)
                    .textContentType(.password)
                Button("Cancel", role: .cancel) { prompt.cancel() }
                Button("Confirm") { prompt.confirm() }
            } message: {
                Text(prompt.message ?? String(localized: "Kids profiles, PINs and deleting profiles need the account's password."))
            }
            .onDisappear { prompt.cancel() }
    }
}
#endif
