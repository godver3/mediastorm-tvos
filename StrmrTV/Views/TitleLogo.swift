import SwiftUI

/// A title's logo in a fixed slot, falling back to the name as text. While the logo URL
/// is still unknown (`pending`) or the logo is loading, the slot stays empty for a short
/// grace period instead of flashing the name in and then swapping it for the logo. The
/// name shows when there is no logo, the load fails, or the grace period runs out.
///
/// The logo is drawn at Title Logo Size (`LogoSettingsStore`) against `size`; the name
/// keeps the full slot, and a larger logo grows the slot.
struct TitleLogo<Fallback: View>: View {
    let url: URL?
    /// The logo URL may still arrive (details metadata is loading).
    var pending = false
    let size: CGSize
    var grace: Duration = .seconds(1.5)
    @ViewBuilder let fallback: () -> Fallback

    @ObservedObject private var settings = LogoSettingsStore.shared
    @State private var graceOver = false

    var body: some View {
        let factor = settings.scale.factor
        let logo = CGSize(width: size.width * factor, height: size.height * factor)
        let slot = CGSize(width: max(size.width, logo.width), height: max(size.height, logo.height))
        Group {
            if let url {
                RemoteImage(url: url, size: logo, contentMode: .fit, alignment: .bottomLeading) { failed in
                    if failed || graceOver {
                        // RemoteImage leaves its placeholder unclipped: the name overflows a
                        // smaller logo's frame into the whole slot.
                        fallback().frame(width: slot.width, height: slot.height, alignment: .bottomLeading)
                    } else {
                        Color.clear
                    }
                }
                .id(url)
            } else if pending && !graceOver {
                Color.clear
            } else {
                fallback()
            }
        }
        .frame(width: slot.width, height: slot.height, alignment: .bottomLeading)
        .task(id: url) {
            graceOver = false
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled else { return }
            graceOver = true
        }
    }
}
