import SwiftUI

/// Shared frame for the first-run screens: the brand logo, title, subtitle, then content,
/// centred in a fixed-width column.
struct OnboardingLayout<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: Text?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 36) {
            BrandMark(height: 190)
            Text(title).font(.title2.weight(.semibold))
            if let subtitle {
                subtitle
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            content
        }
        .frame(maxWidth: 900)
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Inline error under a form, announced to VoiceOver.
struct OnboardingError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .accessibilityLabel(Text("Error: \(message)"))
    }
}

/// Primary action that swaps its label for a spinner while busy.
struct BusyButton: View {
    let title: LocalizedStringKey
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView() }
            }
            .frame(minWidth: 360)
        }
        .disabled(isBusy)
        .accessibilityLabel(Text(title))
    }
}

/// The server's uploaded logo (`/api/branding`), else the bundled MediaStorm logo.
struct BrandMark: View {
    @ObservedObject private var session = AppSession.shared
    var height: CGFloat
    /// Rounded tile, for surfaces whose background differs from the logo's own.
    var tile = false

    var body: some View {
        Group {
            if let url = session.brandLogoURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fit)
                    } else if phase.error != nil {
                        bundled
                    } else {
                        Color.clear
                    }
                }
            } else {
                bundled
            }
        }
        .frame(maxWidth: height * 3, maxHeight: height)
        .frame(height: height)
        .accessibilityLabel(Text("MediaStorm"))
    }

    private var bundled: some View {
        Image("BrandLogo").resizable().aspectRatio(contentMode: .fit)
            .padding(tile ? height * 0.08 : 0)
            .background(tile ? Color.brandBackground : .clear)
            .clipShape(RoundedRectangle(cornerRadius: tile ? height * 0.12 : 0, style: .continuous))
            .shadow(color: .black.opacity(tile ? 0.35 : 0), radius: 20, y: 10)
    }
}

extension Color {
    /// Backdrop of the sign-in screens; matches the bundled logo's own background.
    static let brandBackground = Color(red: 13 / 255, green: 15 / 255, blue: 18 / 255)
}
