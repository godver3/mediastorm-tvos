import AetherEngine
import SwiftUI

/// Several live channels at once (the Expo app's TV multiscreen). Every screen is its own
/// player over its own HLS session (`MultiscreenController`); the remote moves between them
/// by their geometry. The control bar, dialogs and channel picker sit over the tiles.
struct MultiscreenView: View {
    @ObservedObject var controller: MultiscreenController
    @State private var size = CGSize(width: 1920, height: 1080)

    var body: some View {
        let frames = controller.frames(in: size)
        ZStack(alignment: .topLeading) {
            Color.black
            ForEach(controller.slots.indices, id: \.self) { index in
                if let frame = frames[index] {
                    MultiscreenTile(controller: controller, index: index, player: controller.player(index), size: frame.size)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            focusRing(frames[controller.focused])
            if controller.picker == nil, controller.dialog == nil, !controller.controlsOpen {
                MultiscreenRemoteCatcher(handlers: .init(
                    move: { controller.move($0, in: size) }, select: controller.select,
                    longSelect: controller.longSelect, menu: controller.back, other: controller.reveal))
                    .frame(width: size.width, height: size.height)
            }
            if controller.controlsOpen, controller.picker == nil {
                MultiscreenControlBar(controller: controller)
                    .frame(width: size.width, height: MultiscreenController.dockHeight)
                    .offset(y: size.height - MultiscreenController.dockHeight)
            }
            footer
            if let dialog = controller.dialog {
                MultiscreenDialogView(controller: controller, dialog: dialog)
                    .frame(width: size.width, height: size.height)
            }
            if controller.picker != nil {
                LiveView(picker: LivePicker(title: controller.pickerTitle,
                                            playingChannelID: controller.picker?.adding == true ? nil : controller.focusedSlot.channel?.id,
                                            error: controller.exitError,
                                            onPick: controller.pickAction, onClose: controller.closePicker))
                    .padding(.top, 50)
                    .padding(.horizontal, 40)
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.2), value: controller.expanded)
        .animation(.easeOut(duration: 0.2), value: controller.controlsOpen)
    }

    /// A thin white hairline around the focused tile, in the gap: video is never scaled for focus.
    @ViewBuilder private func focusRing(_ frame: CGRect?) -> some View {
        if let frame, controller.picker == nil, controller.overlayVisible || controller.controlsOpen {
            RoundedRectangle(cornerRadius: PosterFocusStyle.cornerRadius, style: .continuous)
                .strokeBorder(PosterFocusStyle.ringColor, lineWidth: PosterFocusStyle.ringWidth)
                .frame(width: frame.width + 8, height: frame.height + 8)
                .offset(x: frame.minX - 4, y: frame.minY - 4)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var footer: some View {
        if controller.picker == nil, controller.overlayVisible || controller.controlsOpen || controller.exiting {
            Text(controller.footerHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .offset(x: MultiscreenController.margin.width,
                        y: controller.controlsOpen ? size.height - 44 : size.height - MultiscreenController.footerHeight - 8)
                .allowsHitTesting(false)
        }
    }
}

/// One screen: its video, a placeholder until there is a picture, and the overlay.
private struct MultiscreenTile: View {
    @ObservedObject var controller: MultiscreenController
    let index: Int
    @ObservedObject var player: MultiscreenTilePlayer
    let size: CGSize

    var body: some View {
        let slot = controller.slots[index]
        let status = MultiscreenTileOverlay.status(slot)
        ZStack(alignment: .bottom) {
            Color(white: 0.08)
            if slot.source != nil, let engine = player.engine {
                AetherPlayerSurface(engine: engine)
            }
            if !player.hasPicture || slot.source == nil {
                placeholder(slot)
            }
            if controller.overlayVisible || controller.controlsOpen || status != nil {
                MultiscreenTileOverlay(slot: slot, programme: MultiscreenProgramme(channel: slot.channel, nowNext: controller.nowNext),
                                       info: player.info, audible: controller.session.audioIndex == index && slot.source != nil,
                                       width: size.width)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PosterFocusStyle.cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: controller.overlayVisible)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("multiscreen.tile.\(index)")
    }

    @ViewBuilder private func placeholder(_ slot: MultiscreenSlot) -> some View {
        VStack(spacing: 16) {
            if let channel = slot.channel {
                ChannelLogo(channel: channel, size: CGSize(width: size.width * 0.3, height: size.height * 0.3))
                if slot.loading || (slot.source != nil && slot.error == nil) { ProgressView() }
            } else {
                Image(systemName: "plus.rectangle.on.rectangle").font(.largeTitle).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
