import SwiftUI

/// The View Switcher pill ("All ▾", "Movies ▾"): a native tvOS menu of Home views, shown
/// when Settings › Home Layout › View Switcher on Home is on and at least one view has no
/// Top Menu tab of its own. It lists All plus those views, with a checkmark on the one Home
/// shows; choosing one shows it on Home. Menu closes it and focus goes back to the pill.
/// It floats centred just under the tab bar, over the hero, so Home's layout doesn't move.
/// Its strip is a full-width focus section, so Down from any tab lands on it and Up from
/// the first row comes back to it.
struct HomeViewSwitcher: View {
    @ObservedObject private var views = HomeViewsStore.shared
    /// The view Home shows.
    let view: String
    /// All plus the views without a tab of their own, in menu order.
    let choices: [String]

    /// Below the tab bar, in the screen's coordinates.
    static let top: CGFloat = 124

    private func title(_ view: String) -> String {
        view == HomeViews.all ? String(localized: "All") : views.label(view)
    }

    private var selection: Binding<String> {
        Binding(get: { view }, set: { views.select($0) })
    }

    var body: some View {
        Menu {
            Picker(selection: selection) {
                ForEach(choices, id: \.self) { choice in
                    Label(title(choice), systemImage: views.icon(choice))
                        .tag(choice)
                        .accessibilityIdentifier("homeView.\(choice)")
                }
            } label: {
                Text("Home View")
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: views.icon(view))
                Text(title(view))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .font(.callout.weight(.semibold))
        }
        .menuStyle(.button)
        .buttonStyle(PillButtonStyle())
        .accessibilityLabel(Text("Home View"))
        .accessibilityValue(Text(title(view)))
        .accessibilityIdentifier("homeViewSwitcher")
        .frame(maxWidth: .infinity)
        .focusSection()
    }
}

/// The app's glass pill: material at rest, white when focused. No system highlight.
private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background {
                    if isFocused {
                        Capsule().fill(Color.white)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
                .scaleEffect(configuration.isPressed ? 0.97 : isFocused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
