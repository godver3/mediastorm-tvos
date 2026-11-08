#if os(iOS)
import AetherEngine
import SwiftUI
import UIKit

/// The pages the phone player's menus open, as sheets (`MobilePlayerSheets`): Search Online…,
/// Translate…, Switch Source and Stream Info. The subtitle pages pause playback while they are up,
/// as the TV's (`presentSubtitlePage`); dragging a sheet away is Cancel.
extension PlayerViewController {
    func mobileSubtitleSearchPage(_ model: SubtitleSearchModel) -> UIViewController {
        UIViewController.mobilePlayerSheet(
            MobileSubtitleSearchView(
                model: model, heading: request.displayTitle,
                onPick: { [weak self] result, language in
                    self?.closeSubtitlePage { $0.onlineSubtitles.use(result, language: language) }
                },
                onClose: { [weak self] in self?.closeSubtitlePage() }),
            onSwipeDismiss: { [weak self] in self?.closeSubtitlePage() })
    }

    func mobileSubtitleTranslatePage(_ sources: [SubtitleTranslateView.Source], translatable: [TrackInfo]) -> UIViewController {
        UIViewController.mobilePlayerSheet(
            MobileSubtitleTranslateView(
                heading: request.displayTitle, sources: sources,
                onPick: { [weak self] id, language in
                    self?.closeSubtitlePage { player in
                        guard let source = translatable.first(where: { $0.id == id }) else { return }
                        player.onlineSubtitles.translate(
                            source, container: OnlineSubtitles.containerTracks(player.engine.subtitleTracks),
                            to: language.code, position: player.lastKnownPosition)
                    }
                },
                onClose: { [weak self] in self?.closeSubtitlePage() }),
            onSwipeDismiss: { [weak self] in self?.closeSubtitlePage() })
    }

    /// The Settings menu's Stream Info: the Stream tab's rows (the TV's swipe-down tab).
    func presentStreamInfo() {
        guard presentedViewController == nil, !didFinish else { return }
        let info = Self.streamInfo(base: streamInfoBase, engine: engine)
        weak var page: UIViewController?
        let sheet = UIViewController.mobilePlayerSheet(
            MobileStreamInfoView(info: info, onClose: { page?.dismiss(animated: true) }),
            onSwipeDismiss: {})
        page = sheet
        present(sheet, animated: true)
    }
}

extension NativeChrome {
    /// The phone's Switch Source sheet; as `sourcePage`, it dismisses itself before calling back.
    static func mobileSourcePage(heading: String, rows: [SourceSwitchView.Row],
                                 onPick: @escaping @MainActor (SourceSwitch.Option) -> Void,
                                 onCancel: @escaping @MainActor () -> Void) -> UIViewController {
        weak var page: UIViewController?
        let sheet = UIViewController.mobilePlayerSheet(
            MobileSourceSwitchView(
                heading: heading, rows: rows,
                onPick: { option in page?.dismiss(animated: true) { onPick(option) } },
                onClose: { page?.dismiss(animated: true) { onCancel() } }),
            onSwipeDismiss: onCancel)
        page = sheet
        return sheet
    }
}
#endif
