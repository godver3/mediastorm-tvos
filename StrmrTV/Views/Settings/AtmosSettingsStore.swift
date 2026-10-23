import AetherEngine
import Foundation

/// Settings › Playback › Atmos Heights and Speaker Layout: whether TrueHD Atmos and DTS:X keep
/// their heights on this device. Apple TV cannot bitstream either, so by default the engine
/// decodes them to lossless 7.1 and the heights are lost; on, it renders them into the speaker
/// layout and sends Apple Positional Audio, which tvOS delivers to an Atmos receiver or soundbar
/// as Dolby MAT (AetherEngine `objectAudioRendering`). Off by default: the encode is lossy.
@MainActor
final class AtmosSettingsStore: ObservableObject {
    static let shared = AtmosSettingsStore()

    @Published var keepHeights: Bool { didSet { defaults.set(keepHeights, forKey: Keys.keepHeights) } }
    /// The speakers the receiver drives; a soundbar takes any of them.
    @Published var layout: SpatialSpeakerLayout { didSet { defaults.set(layout.rawValue, forKey: Keys.layout) } }

    /// Whether this build carries the object renderer (the StrmrEngine package's traits).
    static let isAvailable = AetherEngine.OptionalComponent.trueHDObjectAudio.isBuiltIn

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let keepHeights = "strmrtv.atmosKeepHeights"
        static let layout = "strmrtv.atmosSpeakerLayout"
    }

    private init() {
        keepHeights = defaults.bool(forKey: Keys.keepHeights)
        layout = defaults.string(forKey: Keys.layout).flatMap(SpatialSpeakerLayout.init(rawValue:)) ?? .l714
    }

    /// The load option for a VOD session.
    var rendering: ObjectAudioRendering {
        keepHeights && Self.isAvailable ? .apac(layout) : .off
    }
}
