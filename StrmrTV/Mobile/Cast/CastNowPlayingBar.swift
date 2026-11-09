#if os(iOS)
import SwiftUI

/// "Casting to …" under the tabs while a cast runs: tap for the remote, play / pause in place
/// (the Expo app's now-playing pill).
struct CastNowPlayingBar: View {
    @ObservedObject private var cast = CastController.shared
    /// In the tab bar's accessory (glass already drawn by the system).
    var inAccessory = false

    var body: some View {
        if let session = cast.session {
            HStack(spacing: 12) {
                Button { CastPresenter.showRemote() } label: {
                    HStack(spacing: 12) {
                        Image.castIcon(pointSize: 18).foregroundStyle(.tint).frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            HStack(spacing: 6) {
                                if session.isLive {
                                    Text("LIVE").font(.caption2.weight(.heavy)).foregroundStyle(.red)
                                }
                                Text("Casting to \(session.device.name)").font(.caption).foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if session.phase == .active {
                    Button { cast.togglePlayPause() } label: {
                        Image(systemName: session.state.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(session.state.isPlaying ? "Pause" : "Play")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, inAccessory ? 4 : 10)
            .frame(maxWidth: .infinity)
            .background(inAccessory ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial))
            .overlay(alignment: .top) { if !inAccessory { Divider() } }
            .accessibilityIdentifier("cast.nowPlaying")
        }
    }
}
#endif
