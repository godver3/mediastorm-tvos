import Foundation

// The iroh-bridge C ABI (Vendor/IrohBridge.xcframework, from the Expo app's Rust crate).
// Declared here rather than through its header, as the Expo module does. Each call returns a
// heap JSON string, `{"ok":true,…}` or `{"ok":false,"error":…}`, released with free_string.
@_silgen_name("iroh_ios_bridge_resolve_code")
private func iroh_resolve_code(_ code: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("iroh_ios_bridge_start_proxy")
private func iroh_start_proxy(_ invite: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("iroh_ios_bridge_invalidate_proxy")
private func iroh_invalidate_proxy() -> UnsafeMutablePointer<CChar>?
@_silgen_name("iroh_ios_bridge_network_change")
private func iroh_network_change() -> UnsafeMutablePointer<CChar>?
@_silgen_name("iroh_ios_bridge_get_path_diagnostics")
private func iroh_get_path_diagnostics() -> UnsafeMutablePointer<CChar>?
@_silgen_name("iroh_ios_bridge_free_string")
private func iroh_free_string(_ value: UnsafeMutablePointer<CChar>?)

/// Blocking iroh calls, run off the main thread. One loopback proxy exists at a time; starting
/// it again with the same invite reuses the running one.
enum IrohBridge {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// A connection code (`mshost-…`) looked up on the mainline DHT: the server's invite.
    /// Up to about 90 s (three 30 s attempts) when the code is unknown.
    static func resolve(code: String) async throws -> String {
        let result = try await call { code.withCString { iroh_resolve_code($0) } }
        guard let invite = result["invite"] as? String, !invite.isEmpty else { throw Failure(message: "No invite for that code") }
        return invite
    }

    /// Starts (or reuses) the loopback proxy that tunnels HTTP to the server over iroh.
    /// Returns its base URL, `http://127.0.0.1:<port>`, without the `/api` the bridge appends.
    static func startProxy(invite: String) async throws -> URL {
        let result = try await call { invite.withCString { iroh_start_proxy($0) } }
        guard let raw = result["url"] as? String, var url = URL(string: raw) else { throw Failure(message: "The bridge returned no address") }
        if url.lastPathComponent == "api" { url.deleteLastPathComponent() }
        return URL(string: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) ?? url
    }

    /// Tears the proxy down; also unblocks a start that hangs on a dead path.
    static func invalidateProxy() async {
        _ = try? await call { iroh_invalidate_proxy() }
    }

    /// The network changed (or the app woke): iroh rescans its paths instead of waiting out
    /// its idle timeout on a dead one.
    static func networkChanged() async {
        _ = try? await call { iroh_network_change() }
    }

    /// Whether the connection runs direct or through a relay, for Settings.
    static func pathDiagnostics() async -> [String: Any] {
        (try? await call { iroh_get_path_diagnostics() }) ?? [:]
    }

    private static func call(_ body: @escaping @Sendable () -> UnsafeMutablePointer<CChar>?) async throws -> [String: Any] {
        let text: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let pointer = body()
                defer { iroh_free_string(pointer) }
                continuation.resume(returning: pointer.map { String(cString: $0) })
            }
        }
        guard let text, let data = text.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure(message: "The bridge returned nothing") }
        guard json["ok"] as? Bool == true else {
            throw Failure(message: json["error"] as? String ?? "Remote access failed")
        }
        return json
    }
}
