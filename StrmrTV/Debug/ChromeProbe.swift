#if DEBUG
import AVKit
import UIKit

/// Debug-only: plays Apple's public multi-language HLS sample in a stock
/// AVPlayerViewController so the native transport bar can be inspected on the
/// simulator (where AetherEngine always takes its software route). Launch with
/// `-StrmrChromeProbe 1`.
@MainActor
enum ChromeProbe {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "StrmrChromeProbe") }

    static func present() {
        let url = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!
        let vc = ProbePlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.modalPresentationStyle = .fullScreen
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        // At launch the window may not be key yet (or have its root) when this runs.
        guard let root = (scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first)?.rootViewController else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { present() }
            return
        }
        root.present(vc, animated: false) {
            vc.player?.play()
        }
    }
}

final class ProbePlayerViewController: AVPlayerViewController {
    static var hideNative: Bool { UserDefaults.standard.bool(forKey: "StrmrProbeHideNative") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = [
            TrackMenuItem(id: 2, title: "English", detail: "FLAC 5.1", isSelected: true),
            TrackMenuItem(id: 1, title: "English", detail: "AC-3 Stereo · Commentary", isSelected: false),
            TrackMenuItem(id: 3, title: "Italian", detail: "FLAC 5.1", isSelected: false),
        ]
        var menus = [NativeChrome.audioMenu(items) { id in
            let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
            try? "\(id)".write(toFile: dir + "/probe-selected.txt", atomically: true, encoding: .utf8)
        }]
        // `-StrmrProbeSubtitles N`: a Subtitles menu with N tracks, for long-list checks.
        let count = UserDefaults.standard.integer(forKey: "StrmrProbeSubtitles")
        if count > 0 {
            let languages = ["English", "English", "Spanish", "French", "German", "Japanese", "Portuguese", "Italian"]
            // `-StrmrProbeSubtitleNames`: dup / unique / plain (one-line) / long / longtitle / mixed names
            // (held-Down layout checks); other values mix languages.
            let names = UserDefaults.standard.string(forKey: "StrmrProbeSubtitleNames")
            let subtitles = (0..<count).map { index in
                switch names {
                case "dup": TrackMenuItem(id: index + 10, title: "English", detail: "SUBRIP", isSelected: index == 0)
                case "mixed": TrackMenuItem(id: index + 10, title: languages[index % languages.count],
                                            detail: index % 3 == 0 ? nil : (index % 3 == 1 ? "SDH · SRT"
                                                : "Forced · Signs & Songs [Group] (Modified, Netflix rip) · ASS"), isSelected: index == 0)
                case "long": TrackMenuItem(id: index + 10, title: languages[index % languages.count],
                                           detail: index % 2 == 0 ? "SDH · SRT"
                                               : "Forced · Signs & Songs [Group] (Modified, Netflix rip) · ASS",
                                           isSelected: index == 0)
                case "longtitle": TrackMenuItem(id: index + 10,
                                                title: "Signs & Songs [Group] (Modified, Netflix rip) \(index)",
                                                detail: "SRT", isSelected: index == 0)
                case "plain": TrackMenuItem(id: index + 10, title: "Track \(index + 1) · SUBRIP", detail: nil,
                                            isSelected: index == 0)
                case "unique": TrackMenuItem(id: index + 10, title: "Track \(index + 1)", detail: "SUBRIP",
                                             isSelected: index == 0)
                default: TrackMenuItem(id: index + 10, title: languages[index % languages.count],
                                       detail: index % 3 == 0 ? "SRT · Forced" : "SUBRIP", isSelected: index == 0)
                }
            }
            menus.append(NativeChrome.subtitleMenu(subtitles, offSelected: false, style: SubtitleStyleStore.shared.style,
                                                   onSelect: { _ in }, onStyle: { _ in },
                                                   onSearch: {}, onTranslate: {}))
        }
        // `-StrmrProbeSources 1`: the Settings menu with Switch Source… (a list of fake sources).
        if UserDefaults.standard.bool(forKey: "StrmrProbeSources") { menus.append(probeSettingsMenu()) }
        transportBarCustomMenuItems = menus
    }

    private let hider = TransportSettingsHider()

    /// As the player: Settings › Switch Source… opens the wide list (fake sources).
    private func probeSettingsMenu() -> UIMenu {
        let sources = NativeChrome.switchSourceAction { [weak self] in
            let fake: [(String, String, Int64, [String: Any], String)] = [
                ("Movie.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC.TrueHD.Atmos.7.1-GROUP", "usenet", 58_200_000_000,
                 ["resolution": "2160p", "hasDV": "true", "hdr": "HDR10", "codec": "hevc"], "healthy"),
                ("Movie.2024.1080p.AMZN.WEB-DL.DDP5.1.H.264-GROUP", "debrid", 6_900_000_000,
                 ["resolution": "1080p", "tracker": "RealDebrid"], "cached"),
                ("Movie.2024.720p.WEBRip.x264-GROUP", "debrid", 1_200_000_000,
                 ["resolution": "720p", "tracker": "Torrentio"], "not_cached"),
            ]
            let results = fake.enumerated().compactMap { index, f in
                SourceResult(["title": f.0, "serviceType": f.1, "indexer": "Probe", "sizeBytes": f.2,
                              "attributes": f.3, "sourceHealth": ["state": f.4]], index: index)
            }
            let options = SourceSwitch.options(results, health: [:], current: .init(releaseName: fake[1].0))
            let page = NativeChrome.sourcePage(
                heading: "Movie (2024)", rows: SourceSwitchView.Row.rows(options, results: results, health: [:]),
                onPick: { option in
                    let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
                    try? "\(option.resultIndex ?? -1)".write(toFile: dir + "/probe-source.txt", atomically: true, encoding: .utf8)
                }, onCancel: {})
            self?.present(page, animated: true)
        }
        return NativeChrome.settingsMenu(speeds: [0.5, 1, 1.5, 2], current: 1, extra: [sources]) { _ in }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if Self.hideNative { hider.start(on: view, hiding: [TransportSettingsHider.audible, TransportSettingsHider.legible]) }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyInfoPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [weak self] in self?.dump() }
    }

    /// `-StrmrProbeArtwork URL` (with optional `-StrmrProbeTitle`, `-StrmrProbeSubtitle`,
    /// `-StrmrProbeDescription`): the Info tab as the player builds it, artwork included.
    private func applyInfoPanel() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "StrmrProbeArtwork"), let url = URL(string: raw),
              let item = player?.currentItem else { return }
        let items = EnginePlayerViewController.infoPanelItems(
            title: defaults.string(forKey: "StrmrProbeTitle") ?? "Probe",
            subtitle: defaults.string(forKey: "StrmrProbeSubtitle"),
            description: defaults.string(forKey: "StrmrProbeDescription"))
        item.externalMetadata = items
        // The Stream tab beside Info, with sample rows, for comparing the two panels.
        let stream = StreamInfoViewController()
        stream.update(StreamInfo(file: "Movie.2024.2160p.UHD.BluRay.REMUX.DV.HDR.HEVC.TrueHD.Atmos-GRP.mkv",
                                 source: "Debrid · Real-Debrid", video: "3840×2160 (4K) · HEVC Main 10 · 23.976 fps",
                                 dynamicRange: "Dolby Vision Profile 8", audio: "TrueHD · 7.1 · Atmos · English"))
        customInfoViewControllers = [stream]
        Task {
            guard let image = await EnginePlayerViewController.infoArtwork(from: url),
                  let artwork = EnginePlayerViewController.artworkItem(image) else { return }
            item.externalMetadata = items + [artwork]
        }
    }

    func dump() {
        var lines: [String] = []
        func walk(_ v: UIView, _ depth: Int) {
            let ax = [v.accessibilityIdentifier, v.accessibilityLabel].compactMap { $0 }.joined(separator: " | ")
            lines.append(String(repeating: "  ", count: depth) + "\(type(of: v)) hidden=\(v.isHidden) a=\(v.alpha) \(ax)")
            v.subviews.forEach { walk($0, depth + 1) }
        }
        walk(view, 0)
        let dir = ProcessInfo.processInfo.environment["STRMR_SHOT_DIR"] ?? NSTemporaryDirectory()
        try? lines.joined(separator: "\n").write(toFile: dir + "/viewtree.txt", atomically: true, encoding: .utf8)
    }
}
#endif
