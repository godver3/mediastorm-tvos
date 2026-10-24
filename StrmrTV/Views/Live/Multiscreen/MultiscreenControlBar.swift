import SwiftUI

/// The dock under the tiles: the focused screen's details, then Add screen, Change channel,
/// Retry, Remove, Equal tiles and Guide (exit). Up or Menu returns to the tiles.
struct MultiscreenControlBar: View {
    @ObservedObject var controller: MultiscreenController
    @FocusState private var focus: Control?
    @State private var now = Date()

    enum Control: Hashable {
        case add, change, retry, remove, equal, exit
    }

    var body: some View {
        let slot = controller.focusedSlot
        HStack(alignment: .center, spacing: 40) {
            MultiscreenDockDetails(slot: slot, programme: MultiscreenProgramme(channel: slot.channel, nowNext: controller.nowNext),
                                   info: controller.players[controller.focused]?.info,
                                   audible: controller.session.audioIndex == controller.focused && slot.source != nil,
                                   status: controller.exitError ?? slot.error, now: now)
            HStack(spacing: 12) {
                action(.add, "Add screen", "plus", controller.addScreen)
                action(.change, slot.channel == nil ? "Add channel" : "Change channel", "arrow.left.arrow.right",
                       controller.changeChannel)
                if slot.channel != nil, slot.error != nil {
                    action(.retry, "Retry", "arrow.clockwise", controller.retry)
                }
                if slot.channel != nil {
                    action(.remove, "Remove", "minus", controller.remove)
                }
                action(.equal, "Equal tiles", "square.grid.2x2", controller.equalTiles)
                action(.exit, "Guide", "rectangle.portrait.and.arrow.right", controller.exit)
            }
            .focusSection()
        }
        .padding(.horizontal, MultiscreenController.margin.width)
        .padding(.top, 20)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .defaultFocus($focus, .add)
        .onMoveCommand { if $0 == .up { controller.controlsOpen = false } }
        .onExitCommand { controller.back() }
        .onChange(of: focus) { controller.reveal() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                now = Date()
            }
        }
    }

    private func action(_ control: Control, _ title: LocalizedStringKey, _ symbol: String,
                        _ perform: @escaping () -> Void) -> some View {
        Button {
            controller.reveal()
            perform()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 128, height: 104)
        }
        .buttonStyle(MultiscreenDockButtonStyle())
        .focused($focus, equals: control)
        .accessibilityIdentifier("multiscreen.\(control)")
    }
}

/// A flat dock button that turns white under focus, as the guide's cells do.
struct MultiscreenDockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DockButtonBody(configuration: configuration)
    }

    private struct DockButtonBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.black : Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isFocused ? Color.white : Color.white.opacity(0.08))
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// The stability warning, the stream-limit replacement choice, and notices.
struct MultiscreenDialogView: View {
    @ObservedObject var controller: MultiscreenController
    let dialog: MultiscreenController.Dialog

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(alignment: .leading, spacing: 18) {
                switch dialog {
                case .warning:
                    Text("More screens, higher load").font(.title3.weight(.bold))
                    Text("Additional screens may cause buffering, overheating, or crashes on some devices.")
                        .font(.callout).foregroundStyle(.secondary)
                    button("Cancel", id: "warning.cancel", action: controller.dismissDialog).prefersDefaultFocus(true, in: scope)
                    button("Continue", id: "warning.continue", action: controller.acceptWarning)
                case let .replacement(channel):
                    Text("Stream limit reached").font(.title3.weight(.bold))
                    Text("Replace a screen, or cancel and choose a source with available capacity.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(channel.name).font(.callout.weight(.semibold))
                    ForEach(controller.session.occupied, id: \.self) { index in
                        let name = controller.slots[index].channel?.name ?? String(localized: "Empty")
                        button("Screen \(index + 1) · \(name)", id: "replace.\(index)") { controller.replace(index, with: channel) }
                    }
                    button("Cancel", id: "replace.cancel", action: controller.dismissDialog)
                case let .notice(text):
                    Text(text).font(.callout)
                    button("OK", id: "notice.ok", action: controller.dismissDialog)
                }
            }
            .padding(36)
            .frame(width: 720, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(white: 0.14)))
            .focusScope(scope)
            .focusSection()
        }
        .onExitCommand { controller.back() }
    }

    @Namespace private var scope

    private func button(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("multiscreen.\(id)")
    }
}
