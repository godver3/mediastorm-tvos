import SwiftUI

/// A title's logo in a fixed slot, falling back to the name as text. While the logo URL
/// is still unknown (`pending`) or the logo is loading, the slot stays empty for a short
/// grace period instead of flashing the name in and then swapping it for the logo. The
/// name shows when there is no logo, the load fails, or the grace period runs out.
struct TitleLogo<Fallback: View>: View {
    let url: URL?
    /// The logo URL may still arrive (details metadata is loading).
    var pending = false
    let size: CGSize
    var grace: Duration = .seconds(1.5)
    @ViewBuilder let fallback: () -> Fallback

    @State private var graceOver = false

    var body: some View {
        Group {
            if let url {
                RemoteImage(url: url, size: size, contentMode: .fit, alignment: .bottomLeading) { failed in
                    if failed || graceOver { fallback() } else { Color.clear }
                }
                .id(url)
            } else if pending && !graceOver {
                Color.clear
            } else {
                fallback()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .task(id: url) {
            graceOver = false
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            graceOver = true
        }
    }
}
