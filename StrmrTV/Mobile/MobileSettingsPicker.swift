#if os(iOS)
import SwiftUI

/// A phone Settings choice as a system `Picker`: with a `defaultValue`, the first option,
/// "Default (…)", is nil and follows the server; the others override it on this device. The
/// phone counterpart of the TV's `ChoiceRow`, built on the same `Choice` values so both
/// list the same options.
struct MobileOverridePicker<Value: Hashable>: View {
    enum Style { case menu, navigationLink }

    let title: Text
    @Binding var selection: Value?
    let defaultValue: Value?
    let choices: [ChoiceRow<Value>.Choice]
    var style: Style = .menu

    init(_ title: LocalizedStringKey, selection: Binding<Value?>, defaultValue: Value?,
         choices: [ChoiceRow<Value>.Choice], style: Style = .menu) {
        self.init(title: Text(title), selection: selection, defaultValue: defaultValue, choices: choices, style: style)
    }

    init(title: Text, selection: Binding<Value?>, defaultValue: Value?,
         choices: [ChoiceRow<Value>.Choice], style: Style = .menu) {
        self.title = title
        _selection = selection
        self.defaultValue = defaultValue
        self.choices = choices
        self.style = style
    }

    /// A setting with no server default: always one of `choices`.
    init(_ title: LocalizedStringKey, selection: Binding<Value>, choices: [ChoiceRow<Value>.Choice],
         style: Style = .menu) {
        self.init(title: Text(title),
                  selection: Binding(get: { selection.wrappedValue },
                                     set: { if let value = $0 { selection.wrappedValue = value } }),
                  defaultValue: nil, choices: choices, style: style)
    }

    var body: some View {
        switch style {
        case .menu: picker.pickerStyle(.menu)
        case .navigationLink: picker.pickerStyle(.navigationLink)
        }
    }

    private var picker: some View {
        Picker(selection: $selection) {
            if let defaultValue {
                let fallback = choices.first { $0.value == defaultValue }
                option(Text("Default (\(fallback?.name ?? Text(verbatim: "\(defaultValue)")))"), swatch: fallback?.swatch)
                    .tag(Value?.none)
            }
            ForEach(choices) { choice in
                option(choice.name, swatch: choice.swatch).tag(Optional(choice.value))
            }
        } label: {
            title
        }
    }

    @ViewBuilder
    private func option(_ name: Text, swatch: String?) -> some View {
        if let swatch, style == .navigationLink {
            HStack(spacing: 12) {
                MobileSwatch(hex: swatch)
                name
            }
        } else {
            name
        }
    }
}

/// A small colour dot for a colour choice.
struct MobileSwatch: View {
    let hex: String
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(Color(uiColor: UIColor(hex: hex)))
            .overlay(Circle().strokeBorder(.secondary.opacity(0.6), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum MobileChoices {
    /// On / Off, the choices of most device overrides.
    static var onOff: [ChoiceRow<Bool>.Choice] {
        [.init(value: true, name: String(localized: "On")), .init(value: false, name: String(localized: "Off"))]
    }
}
#endif
