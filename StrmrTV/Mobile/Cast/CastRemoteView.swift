#if os(iOS)
import SwiftUI

/// Casting to …: what plays on the TV, with its artwork, a scrubber, skip back / play-pause /
/// skip forward, the TV's volume and Stop Casting (the Expo app's cast controller).
struct CastRemoteView: View {
    @ObservedObject private var cast = CastController.shared
    @Environment(\.dismiss) private var dismiss
    /// The scrubber's position while a finger is on it.
    @State private var scrubbing: Double?
    @State private var volume: Float?

    var body: some View {
        NavigationStack {
            Group {
                if let session = cast.session {
                    content(session)
                } else {
                    ContentUnavailableView {
                        Label { Text("Nothing Is Casting") } icon: { Image.castIcon(pointSize: 44) }
                    } description: {
                        Text("Start a cast from a title to control it here.")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        cast.dismissFailure()
                        dismiss()
                    }
                }
            }
        }
        .accessibilityIdentifier("cast.remote")
    }

    @ViewBuilder
    private func content(_ session: CastController.Session) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                if session.isLive { channelLogo(session.artworkURL) } else { artwork(session.artworkURL) }
                VStack(spacing: 4) {
                    Text(session.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    if let subtitle = session.subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Label { Text(statusLine(session)) } icon: { Image.castIcon(pointSize: 14) }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.tint)
                        .padding(.top, 6)
                }
                switch session.phase {
                case .connecting:
                    ProgressView().controlSize(.large).padding(.top, 12)
                case let .failed(message):
                    VStack(spacing: 12) {
                        Label("Couldn't Cast", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(.orange)
                        Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                case .active:
                    controls(session)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func statusLine(_ session: CastController.Session) -> String {
        switch session.phase {
        case .connecting: String(localized: "Connecting to \(session.device.name)…")
        case .failed: session.device.name
        case .active:
            session.state.phase == .buffering || session.state.phase == .loading
                ? String(localized: "Buffering on \(session.device.name)")
                : String(localized: "Casting to \(session.device.name)")
        }
    }

    /// A channel's logo, fitted on a 16:9 tile.
    private func channelLogo(_ url: URL?) -> some View {
        RoundedRectangle(cornerRadius: 14).fill(.quaternary)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit).padding(28)
                } placeholder: {
                    Image(systemName: "tv").font(.largeTitle).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 360)
            .padding(.top, 8)
    }

    private func artwork(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().aspectRatio(contentMode: .fit)
        } placeholder: {
            RoundedRectangle(cornerRadius: 14).fill(.quaternary)
                .overlay { Image(systemName: "film").font(.largeTitle).foregroundStyle(.tertiary) }
                .aspectRatio(2 / 3, contentMode: .fit)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .frame(maxHeight: 300)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func controls(_ session: CastController.Session) -> some View {
        if session.isLive {
            liveControls(session)
        } else {
            timeline(session)
            transport(session)
        }
        volumeAndStop(session)
    }

    /// A channel: LIVE where the scrubber would be, and play / pause alone.
    @ViewBuilder
    private func liveControls(_ session: CastController.Session) -> some View {
        Text("LIVE")
            .font(.caption.weight(.heavy))
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.red, in: Capsule())
            .accessibilityLabel("Live")
            .accessibilityIdentifier("cast.live")
        Button { cast.togglePlayPause() } label: {
            Image(systemName: session.state.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(session.state.isPlaying ? "Pause" : "Play")
    }

    @ViewBuilder
    private func timeline(_ session: CastController.Session) -> some View {
        let state = session.state
        let duration = max(state.duration, 0)
        let position = scrubbing ?? min(state.position, duration > 0 ? duration : state.position)
        VStack(spacing: 6) {
            Slider(value: Binding(get: { position }, set: { scrubbing = $0 }), in: 0...max(duration, 1)) { editing in
                if !editing, let target = scrubbing {
                    cast.seek(to: target)
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        scrubbing = nil
                    }
                }
            }
            .disabled(!session.canSeek || duration <= 0)
            HStack {
                Text(formatTimestamp(position))
                Spacer()
                Text(duration > 0 ? "-" + formatTimestamp(max(duration - position, 0)) : "--:--")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            if !session.canSeek {
                Text("Seeking isn't available for this stream.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func transport(_ session: CastController.Session) -> some View {
        let state = session.state
        return HStack(spacing: 44) {
            Button { cast.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                .disabled(!session.canSeek)
                .accessibilityLabel("Skip Back 10 Seconds")
            Button { cast.togglePlayPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44))
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            Button { cast.skip(by: 30) } label: { Image(systemName: "goforward.30") }
                .disabled(!session.canSeek)
                .accessibilityLabel("Skip Forward 30 Seconds")
        }
        .font(.system(size: 30))
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func volumeAndStop(_ session: CastController.Session) -> some View {
        if let current = session.state.volume {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(volume ?? current) }, set: { volume = Float($0) }), in: 0...1) { editing in
                    if !editing, let volume {
                        cast.setVolume(volume)
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            self.volume = nil
                        }
                    }
                }
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("TV Volume")
        }

        Button(role: .destructive) { cast.stop() } label: {
            Label("Stop Casting", systemImage: "stop.fill").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .padding(.top, 8)
        .accessibilityIdentifier("cast.stop")
    }
}
#endif
