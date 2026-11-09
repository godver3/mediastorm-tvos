#if os(iOS)
import AVKit
import UIKit

/// The phone player's own controls, over the video.
///
/// On the native route AVKit draws the transport (scrubber, play / pause, skip, Picture in
/// Picture, AirPlay, volume, close) and this view adds only what AVKit's iOS chrome has no API
/// for: the Audio / Subtitles / Settings menus (the TV's `NativeChrome` menus, as menu buttons) and
/// the Skip Intro / Next Episode button. The menus fade in and out with AVKit's chrome
/// (`MobileChromeVisibility`); the skip button stays up while its segment plays, as the TV's
/// contextual action.
///
/// On the software route (dav1d / VP9) there is no AVPlayer, so AVKit shows nothing and this view
/// is the whole transport (`setOwnsTransport(true)`), laid out as AVKit's: close and title at the
/// top, AirPlay at the top trailing corner, skip back / play-pause / skip forward in the middle,
/// and the scrubber along the bottom with seek previews above it.
final class MobilePlayerControls: UIView {
    /// The transport's callbacks (software route).
    var onClose: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    /// The scrubber moved to a time (nil when the finger lifts, with the time to seek to).
    var onScrub: ((_ time: Double, _ ended: Bool) -> Void)?
    /// The chrome was shown by a tap (so menus and previews can refresh).
    var onShow: (() -> Void)?

    /// Everything that fades with the chrome; the skip button sits outside it.
    let chrome = UIView()
    let transport = MobileTransportView()
    private let menuRow = UIStackView()
    private var actionButton: UIButton?
    /// The skip button's bottom: above AVKit's bottom bar (native route), or above the menu row.
    private var actionOverlayBottom: NSLayoutConstraint?
    private var actionTransportBottom: NSLayoutConstraint?
    private(set) var ownsTransport = false
    private var hideWork: DispatchWorkItem?
    private var paused = false
    private var menuOpen = false

    /// Where the menu row sits over AVKit's chrome (native route) or the own transport.
    private var rowOverlayConstraints: [NSLayoutConstraint] = []
    private var rowTransportConstraints: [NSLayoutConstraint] = []

    /// Where the chrome is headed: its opacity stays 1 through a fade out (glass buttons drop
    /// their glass at once when it doesn't), so this, not `chrome.alpha`, says whether it shows.
    private(set) var isChromeVisible = false

    init(title: String, subtitle: String?) {
        super.init(frame: .zero)
        chrome.alpha = 0
        transport.setTitle(title, subtitle: subtitle)
        transport.isHidden = true
        transport.onClose = { [weak self] in self?.onClose?() }
        transport.onPlayPause = { [weak self] in
            self?.onPlayPause?()
            self?.flash()
        }
        transport.onSkip = { [weak self] delta in
            self?.onSkip?(delta)
            self?.flash()
        }
        transport.onScrub = { [weak self] time, ended in
            self?.onScrub?(time, ended)
            self?.flash()
        }
        menuRow.axis = .horizontal
        menuRow.spacing = 10
        for view in [chrome, transport, menuRow] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(chrome)
        chrome.addSubview(transport)
        chrome.addSubview(menuRow)
        let guide = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            transport.topAnchor.constraint(equalTo: topAnchor),
            transport.bottomAnchor.constraint(equalTo: bottomAnchor),
            transport.leadingAnchor.constraint(equalTo: leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        // Over AVKit: top trailing, beside AVKit's own volume / zoom group, so it never covers the
        // scrubber or AVKit's bottom buttons.
        rowOverlayConstraints = [
            menuRow.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -Self.overlayInset.width),
            menuRow.topAnchor.constraint(equalTo: guide.topAnchor, constant: Self.overlayInset.height),
        ]
        rowTransportConstraints = [
            menuRow.trailingAnchor.constraint(equalTo: transport.barGuide.trailingAnchor),
            menuRow.bottomAnchor.constraint(equalTo: transport.barGuide.topAnchor, constant: -12),
        ]
        NSLayoutConstraint.activate(rowOverlayConstraints)
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Where the menu row sits on the native route, from the safe area's top trailing corner
    /// (`MobileChromeVisibility` measures AVKit's top bar and moves it in line).
    static var overlayInset = CGSize(width: 16, height: 12)

    func setOverlayTop(_ top: CGFloat, trailing: CGFloat) {
        rowOverlayConstraints.first?.constant = -trailing
        rowOverlayConstraints.last?.constant = top
    }

    /// Only the controls take touches; elsewhere AVKit's chrome (native route) gets them, except
    /// on the software route, where a tap anywhere shows or hides the transport.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        if view is UIControl || view is AVRoutePickerView || view?.superview is AVRoutePickerView { return view }
        if let view, view.isDescendant(of: transport.bar) { return view }
        return ownsTransport ? self : nil
    }

    // MARK: Route

    /// The software route: this view is the whole transport.
    func setOwnsTransport(_ owns: Bool) {
        guard owns != ownsTransport else { return }
        ownsTransport = owns
        transport.isHidden = !owns
        NSLayoutConstraint.deactivate(owns ? rowOverlayConstraints : rowTransportConstraints)
        NSLayoutConstraint.activate(owns ? rowTransportConstraints : rowOverlayConstraints)
        placeActionButton()
        if owns { flash() } else { setChrome(visible: false) }
    }

    private func placeActionButton() {
        actionOverlayBottom?.isActive = !ownsTransport
        actionTransportBottom?.isActive = ownsTransport
    }

    // MARK: Menus and the skip button

    /// The TV's transport-bar menus as menu buttons: tap opens the menu.
    func setMenus(_ menus: [UIMenu]) {
        let buttons = menuRow.arrangedSubviews.compactMap { $0 as? UIButton }
        if buttons.count == menus.count {
            zip(buttons, menus).forEach { button, menu in
                button.menu = menu
                button.accessibilityLabel = Self.name(menu)
            }
            return
        }
        buttons.forEach { $0.removeFromSuperview() }
        for menu in menus {
            menuRow.addArrangedSubview(menuButton(menu))
        }
    }

    private func menuButton(_ menu: UIMenu) -> UIButton {
        var config = Self.glassConfiguration()
        config.image = menu.image
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body, scale: .large)
        let button = UIButton(configuration: config)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        // As built (the track list first), not flipped to start next to a button low on screen.
        button.preferredMenuElementOrder = .fixed
        button.accessibilityLabel = Self.name(menu)
        button.accessibilityIdentifier = "player.menu.\(Self.name(menu))"
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        // While a menu is open the chrome stays up.
        button.addAction(UIAction { [weak self] _ in self?.menuOpened() }, for: .menuActionTriggered)
        return button
    }

    /// A menu's name: its title, or (a title moved off the button's menu) its accessibility label.
    private static func name(_ menu: UIMenu) -> String {
        menu.title.isEmpty ? (menu.accessibilityLabel ?? "") : menu.title
    }

    private func menuOpened() {
        menuOpen = true
        hideWork?.cancel()
        // The menu closing has no event of its own; the next flash or tap releases it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.menuOpen = false
            if self?.ownsTransport == true { self?.flash() }
        }
    }

    /// Skip Intro / Skip Recap / Next Episode (with its countdown), bottom trailing, shown with or
    /// without the chrome while its segment plays.
    func setAction(_ action: UIAction?) {
        guard let action else {
            actionButton?.removeFromSuperview()
            actionButton = nil
            return
        }
        if let actionButton {
            var config = actionButton.configuration
            config?.title = action.title
            config?.image = action.image
            actionButton.configuration = config
            actionButton.removeTarget(nil, action: nil, for: .allEvents)
            actionButton.enumerateEventHandlers { handler, _, event, _ in
                if let handler { actionButton.removeAction(handler, for: event) }
            }
            actionButton.addAction(action, for: .primaryActionTriggered)
            return
        }
        var config = Self.glassConfiguration(prominent: true)
        config.title = action.title
        config.image = action.image
        config.imagePadding = 8
        config.buttonSize = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .headline)
            return attributes
        }
        let button = UIButton(configuration: config, primaryAction: action)
        button.accessibilityIdentifier = "player.skip"
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        actionOverlayBottom = button.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -100)
        actionTransportBottom = button.bottomAnchor.constraint(equalTo: menuRow.topAnchor, constant: -14)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        ])
        actionButton = button
        placeActionButton()
    }

    static func glassConfiguration(prominent: Bool = false) -> UIButton.Configuration {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = prominent ? .prominentGlass() : .glass()
        } else {
            config = prominent ? .filled() : .gray()
            config.baseBackgroundColor = prominent ? .white : UIColor.black.withAlphaComponent(0.45)
            config.baseForegroundColor = prominent ? .black : .white
        }
        if prominent, #available(iOS 26.0, *) { config.baseBackgroundColor = .white; config.baseForegroundColor = .black }
        if !prominent { config.baseForegroundColor = .white }
        config.cornerStyle = .capsule
        return config
    }

    // MARK: Visibility

    /// Shows or hides the chrome. On the native route `avkit` is AVKit's volume group layer, which
    /// the menu row sits beside: its running fade's timing and its slide's distance are used, start
    /// time included, so the row comes and goes with AVKit's top bar (a fade with a short slide
    /// down on show, up on hide). Without them (the software route, or AVKit's animation already
    /// over) the same fade runs from now.
    func setChrome(visible: Bool, following avkit: CALayer? = nil) {
        guard visible != isChromeVisible || chrome.layer.animation(forKey: "chrome.opacity") != nil else { return }
        isChromeVisible = visible
        let fade = (avkit?.animation(forKey: "opacity") as? CABasicAnimation).flatMap { fade in
            (((fade.toValue as? NSNumber)?.floatValue ?? 0) > 0.5) == visible ? fade : nil
        }
        let slide = (avkit?.animation(forKey: "position") as? CABasicAnimation)?.fromValue as? NSValue
        let distance = slide.map { -abs($0.cgPointValue.y) } ?? -8
        let current = chrome.layer.presentation()?.opacity ?? Float(chrome.alpha)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fade == nil ? current : (visible ? 0 : 1)
        opacity.toValue = visible ? 1 : 0
        opacity.duration = fade?.duration ?? (ownsTransport ? (visible ? 0.2 : 0.35) : 0.15)
        opacity.beginTime = fade?.beginTime ?? CACurrentMediaTime()
        opacity.timingFunction = fade?.timingFunction ?? CAMediaTimingFunction(name: .linear)
        opacity.fillMode = .both
        opacity.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, isChromeVisible == visible else { return }
            chrome.alpha = visible ? 1 : 0
            chrome.layer.removeAnimation(forKey: "chrome.opacity")
            menuRow.layer.removeAnimation(forKey: "chrome.slide")
        }
        chrome.alpha = 1
        chrome.layer.add(opacity, forKey: "chrome.opacity")
        if ownsTransport {
            menuRow.layer.removeAnimation(forKey: "chrome.slide")
        } else {
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = visible ? distance : 0
            move.toValue = visible ? 0 : distance
            move.duration = opacity.duration
            move.beginTime = opacity.beginTime
            move.timingFunction = opacity.timingFunction
            move.fillMode = .both
            move.isRemovedOnCompletion = false
            menuRow.layer.add(move, forKey: "chrome.slide")
        }
        CATransaction.commit()
    }

    /// AVKit's volume slider is open over the menu row (native route): the row fades out.
    func setMenuRowCovered(_ covered: Bool) {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.menuRow.alpha = covered ? 0 : 1
        }
    }

    /// Software route: shows the transport; it hides after a few seconds unless paused.
    func flash() {
        hideWork?.cancel()
        setChrome(visible: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self, ownsTransport, !paused, !menuOpen, !transport.isScrubbing else { return }
            setChrome(visible: false)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    @objc private func backgroundTapped() {
        guard ownsTransport else { return }
        if isChromeVisible {
            hideWork?.cancel()
            setChrome(visible: false)
        } else {
            flash()
            onShow?()
        }
    }

    // MARK: Software transport

    func update(position: Double, duration: Double, paused: Bool) {
        transport.update(position: position, duration: duration, paused: paused)
        if paused != self.paused {
            self.paused = paused
            if paused { flash() }
        }
    }

    func setDetails(_ text: String?) { transport.setDetails(text) }
}
#endif
