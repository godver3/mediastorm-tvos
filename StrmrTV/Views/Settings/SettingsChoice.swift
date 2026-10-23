import SwiftUI

/// A Settings row showing the current choice that opens a page of every choice, with a
/// checkmark on the current one; picking one returns to the form. With a `defaultValue`,
/// the first choice, "Default (…)", follows the server and the others override it on
/// this device.
///
/// Used in place of `Picker`: on tvOS 27 a Form picker's pushed option list comes up
/// blank on device. This page is built like the Settings subpages that do show.
struct ChoiceRow<Value: Hashable>: View {
    struct Choice: Identifiable {
        let value: Value
        let name: Text
        var swatch: String?
        var id: Value { value }

        init(value: Value, name: String, swatch: String? = nil) {
            self.init(value: value, text: Text(name), swatch: swatch)
        }

        init(value: Value, text: Text, swatch: String? = nil) {
            self.value = value
            self.name = text
            self.swatch = swatch
        }
    }

    let title: Text
    @Binding var selection: Value?
    /// The server's value, shown as the "Default (…)" row; nil when there is no default.
    let defaultValue: Value?
    let choices: [Choice]

    init(title: LocalizedStringKey, selection: Binding<Value?>, defaultValue: Value?, choices: [Choice]) {
        self.init(title: Text(title), selection: selection, defaultValue: defaultValue, choices: choices)
    }

    init(title: Text, selection: Binding<Value?>, defaultValue: Value?, choices: [Choice]) {
        self.title = title
        _selection = selection
        self.defaultValue = defaultValue
        self.choices = choices
    }

    var body: some View {
        NavigationLink {
            ChoiceList(title: title, selection: $selection, rows: rows)
        } label: {
            LabeledContent {
                HStack(spacing: 14) {
                    if let swatch = current?.swatch { Swatch(hex: swatch) }
                    current?.name ?? Text(verbatim: "—")
                }
            } label: {
                title
            }
        }
    }

    fileprivate struct Row: Identifiable {
        let value: Value?
        let name: Text
        var swatch: String?
        var id: String { value.map { "\($0)" } ?? "default" }
    }

    private var rows: [Row] {
        let options = choices.map { Row(value: $0.value, name: $0.name, swatch: $0.swatch) }
        guard let defaultValue else { return options }
        let fallback = choices.first { $0.value == defaultValue }
        let name = fallback?.name ?? Text(verbatim: "\(defaultValue)")
        return [Row(value: nil, name: Text("Default (\(name))"), swatch: fallback?.swatch)] + options
    }

    private var current: Row? { rows.first { $0.value == selection } }

    private struct ChoiceList: View {
        let title: Text
        @Binding var selection: Value?
        let rows: [Row]
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            Form {
                SettingsPageTitle(title)
                Section {
                    ForEach(rows) { row in
                        Button {
                            selection = row.value
                            dismiss()
                        } label: {
                            HStack(spacing: 20) {
                                if let swatch = row.swatch { Swatch(hex: swatch) }
                                row.name
                                Spacer()
                                if row.value == selection { Image(systemName: "checkmark") }
                            }
                        }
                        .buttonStyle(OptionRowStyle())
                        .listRowBackground(Color.clear)
                        // The platter is the row: without this the Form's own row insets
                        // add to its padding and space the options out.
                        .listRowInsets(EdgeInsets())
                        .accessibilityAddTraits(row.value == selection ? .isSelected : [])
                    }
                }
            }
            .settingsSubpage()
            .settingsListMargins(80)
        }
    }
}

extension ChoiceRow {
    /// A setting with no server default: always one of `choices`.
    init(title: LocalizedStringKey, selection: Binding<Value>, choices: [Choice]) {
        self.init(title: Text(title), selection: Binding(get: { selection.wrappedValue },
                                                         set: { if let value = $0 { selection.wrappedValue = value } }),
                  defaultValue: nil, choices: choices)
    }
}

/// An option row's own platter. With the system's, the focused row's text turned white
/// before its white platter faded as the page was popped, so it flashed blank on device;
/// here the text colour and the platter change in one animation.
private struct OptionRowStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background(Capsule().fill(isFocused ? Color.white : Color.white.opacity(0.08)))
            .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.02 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct Swatch: View {
    let hex: String

    var body: some View {
        Circle()
            .fill(Color(uiColor: UIColor(hex: hex)))
            .overlay(Circle().strokeBorder(.secondary, lineWidth: 2))
            .frame(width: 32, height: 32)
    }
}
