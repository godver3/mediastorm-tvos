import SwiftUI

/// Settings > Subtitle Style: the device's `SubtitleStyle`, with a live preview of a
/// 1080p frame on the left drawn by the player's own overlay.
struct SubtitleSettingsView: View {
    @ObservedObject private var store = SubtitleStyleStore.shared
    @State private var confirmReset = false

    var body: some View {
        HStack(alignment: .center, spacing: 60) {
            SubtitlePreview(style: store.style)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            form
                .frame(width: 1040)
        }
        .padding(.horizontal, 30)
        .settingsSubpage()
        .task { await PlaybackCoordinator.shared.refreshSubtitleStyle() }
        .confirmationDialog("Reset every subtitle setting to its default?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var form: some View {
        Form {
            SettingsPageTitle("Subtitle Style")
            Section("Text") {
                ChoiceRow(title: "Size", selection: store.binding(\.size), defaultValue: server.size,
                          choices: Self.choices(SubtitleStyle.sizes, [style.size, server.size]) {
                              SubtitleStyle.sizeName($0) + (SubtitleStyle.sizes.contains($0) ? "" : " (\(Self.scale($0)))")
                          })
                ChoiceRow(title: "Colour", selection: store.binding(\.textColor), defaultValue: server.textColor,
                          choices: Self.colorChoices([style.textColor, server.textColor]))
                ChoiceRow(title: "Opacity", selection: store.binding(\.textOpacity), defaultValue: server.textOpacity,
                          choices: Self.choices(SubtitleStyle.opacities, [style.textOpacity, server.textOpacity],
                                                SubtitleStyle.percent))
                ChoiceRow(title: "Bold", selection: store.binding(\.bold), defaultValue: server.bold, choices: [
                    .init(value: true, name: String(localized: "On")),
                    .init(value: false, name: String(localized: "Off")),
                ])
            }

            Section("Edge") {
                ChoiceRow(title: "Style", selection: store.binding(\.edge), defaultValue: server.edge, choices: [
                    .init(value: .none, name: String(localized: "None")),
                    .init(value: .shadow, name: String(localized: "Drop Shadow")),
                    .init(value: .outline, name: String(localized: "Outline")),
                ])
                if style.edge == .outline {
                    ChoiceRow(title: "Outline Colour", selection: store.binding(\.outlineColor),
                              defaultValue: server.outlineColor,
                              choices: Self.colorChoices([style.outlineColor, server.outlineColor]))
                    ChoiceRow(title: "Outline Width", selection: store.binding(\.outlineWeight),
                              defaultValue: server.outlineWeight,
                              choices: Self.choices(SubtitleStyle.outlineWeights, [style.outlineWeight, server.outlineWeight],
                                                    SubtitleStyle.weightName))
                }
            }

            Section("Background") {
                ChoiceRow(title: "Box Opacity", selection: store.binding(\.backgroundOpacity),
                          defaultValue: server.backgroundOpacity,
                          choices: Self.choices(SubtitleStyle.backgroundOpacities,
                                                [style.backgroundOpacity, server.backgroundOpacity], SubtitleStyle.percent))
                if style.backgroundOpacity > 0 {
                    ChoiceRow(title: "Box Colour", selection: store.binding(\.backgroundColor),
                              defaultValue: server.backgroundColor,
                              choices: Self.colorChoices([style.backgroundColor, server.backgroundColor]))
                }
            }

            Section {
                ChoiceRow(title: "Position", selection: store.binding(\.bottomMargin), defaultValue: server.bottomMargin,
                          choices: Self.choices(SubtitleStyle.margins, [style.bottomMargin, server.bottomMargin],
                                                SubtitleStyle.marginName))
            } header: {
                Text("Placement")
            } footer: {
                Text("Default follows the server's setting for this device or profile; a choice here applies to this Apple TV only. Bitmap subtitles (PGS, DVB, DVD) follow the size.")
            }

            if !store.overrides.isEmpty {
                Section {
                    Button("Reset All to Default") { confirmReset = true }
                }
            }
        }
        .settingsListMargins(50)
    }

    private var style: SubtitleStyle { store.style }
    private var server: SubtitleStyle { store.server }

    /// `options`, plus the current and default values when they are not among them (set on the server).
    private static func choices(_ options: [Double], _ extra: [Double],
                                _ name: (Double) -> String) -> [ChoiceRow<Double>.Choice] {
        Set(options + extra).sorted().map { .init(value: $0, name: name($0)) }
    }

    private static func colorChoices(_ extra: [String]) -> [ChoiceRow<String>.Choice] {
        var entries = SubtitleStyle.palette.map { ChoiceRow<String>.Choice(value: $0.hex, name: $0.name, swatch: $0.hex) }
        for value in extra where !entries.contains(where: { $0.value == value }) {
            entries.append(.init(value: value, name: value.uppercased(), swatch: value))
        }
        return entries
    }

    private static func scale(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }
}

/// A 1920×1080 frame scaled down, with sample text in the player's overlay.
private struct SubtitlePreview: View {
    let style: SubtitleStyle

    var body: some View {
        let scale: CGFloat = 0.38
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.52, blue: 0.72), Color(red: 0.86, green: 0.78, blue: 0.62),
                                    Color(red: 0.25, green: 0.3, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
            OverlayRepresentable(style: style)
        }
        .frame(width: 1920, height: 1080)
        .scaleEffect(scale)
        .frame(width: 1920 * scale, height: 1080 * scale)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private struct OverlayRepresentable: UIViewRepresentable {
        let style: SubtitleStyle

        func makeUIView(context: Context) -> SubtitleOverlayView {
            let view = SubtitleOverlayView()
            view.style = style
            view.showSample(String(localized: "The quick brown fox\njumps over the lazy dog."))
            return view
        }

        func updateUIView(_ view: SubtitleOverlayView, context: Context) {
            view.style = style
        }
    }
}
