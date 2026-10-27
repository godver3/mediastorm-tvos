import UIKit

/// The transport for AetherEngine's software route (AV1/VP9/etc.), where AVKit has no AVPlayer
/// and therefore no transport bar of its own. Laid out as AVKit's tvOS 26 bar so the two routes
/// look the same: a thin full-width bar, elapsed time (with a pause glyph while paused) under its
/// leading end and the time remaining under its trailing end, and the menu buttons in a row above
/// the trailing end that Up focuses. Down opens the Info card; the Skip Intro / Next Episode
/// capsule sits above the row.
final class SoftwareTransportHUD: UIView {
    private let scrim = CAGradientLayer()
    /// Everything that fades in and out with the bar.
    private let chrome = UIView()
    private let track = UIView()
    private let fill = UIView()
    private let playhead = UIView()
    private let elapsedLabel = UILabel()
    private let pauseGlyph = UIImageView(image: UIImage(systemName: "pause.circle"))
    private let remainingLabel = UILabel()
    private let buttonRow = UIStackView()
    private let info: TransportInfoCard
    private var actionButton: TransportActionButton?
    private let preview = ScrubPreviewView()
    private var fraction: CGFloat = 0
    private var previewFraction: CGFloat = 0
    private var hideWork: DispatchWorkItem?
    private var paused = false

    /// The menu row has focus (Up from the bar); the bar dims behind it, as AVKit's does.
    private(set) var rowFocused = false
    /// Called when what the HUD wants focused changes; the player re-runs its focus update.
    var onFocusChange: (() -> Void)?

    var isShowing: Bool { chrome.alpha > 0 }
    var isInfoShowing: Bool { info.alpha > 0 }
    var hasMenus: Bool { !buttonRow.arrangedSubviews.isEmpty }
    /// Whether the player should hand focus to the HUD (its row, or the Skip capsule).
    var wantsFocus: Bool { rowFocused || actionButton != nil }
    var isActionFocused: Bool { actionButton?.isFocused ?? false }

    private static let inset: CGFloat = 80
    /// The bar's centre sits this far above the bottom edge (as AVKit's, about y 910 of 1080).
    private static let barBottom: CGFloat = 170

    init(title: String, subtitle: String? = nil) {
        info = TransportInfoCard(title: title, subtitle: subtitle)
        super.init(frame: .zero)
        scrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.65).cgColor]
        scrim.locations = [0.45, 1]
        chrome.layer.addSublayer(scrim)
        chrome.alpha = 0
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)

        track.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        track.layer.cornerRadius = 5
        track.clipsToBounds = true
        fill.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        playhead.backgroundColor = .white
        track.addSubview(fill)
        track.addSubview(playhead)
        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
            label.textColor = .white
        }
        remainingLabel.textAlignment = .right
        pauseGlyph.tintColor = .white
        pauseGlyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        pauseGlyph.isHidden = true
        let elapsed = UIStackView(arrangedSubviews: [elapsedLabel, pauseGlyph])
        elapsed.spacing = 12
        elapsed.alignment = .center
        buttonRow.spacing = 24

        info.alpha = 0
        preview.alpha = 0
        for view in [track, elapsed, remainingLabel, buttonRow, info] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            chrome.addSubview(view)
        }
        chrome.addSubview(preview)
        NSLayoutConstraint.activate([
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: Self.inset),
            track.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -Self.inset),
            track.centerYAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -Self.barBottom),
            track.heightAnchor.constraint(equalToConstant: 10),
            elapsed.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            elapsed.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 10),
            remainingLabel.trailingAnchor.constraint(equalTo: track.trailingAnchor),
            remainingLabel.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: track.trailingAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: track.topAnchor, constant: -39),
            info.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            info.bottomAnchor.constraint(equalTo: track.topAnchor, constant: -36),
            info.widthAnchor.constraint(lessThanOrEqualToConstant: 1300),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrim.frame = bounds
        let width = track.bounds.width * fraction
        fill.frame = CGRect(x: 0, y: 0, width: width, height: track.bounds.height)
        playhead.frame = CGRect(x: max(0, width - 2), y: 0, width: 2, height: track.bounds.height)
        layoutPreview()
    }

    /// Only the row and the Skip capsule take presses; the rest of the HUD lets them through.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view is UIButton ? view : nil
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if !rowFocused, let actionButton { return [actionButton] }
        return buttonRow.arrangedSubviews
    }

    // MARK: Info card

    func setArtwork(_ image: UIImage) { info.setArtwork(image) }

    func setDetails(_ text: String?) { info.setDetails(text) }

    /// Down on the bar: the Info card, as AVKit's Info tab. Up, Down or Menu closes it.
    func setInfo(visible: Bool) {
        if visible { releaseRow() }
        UIView.animate(withDuration: 0.25) {
            self.info.alpha = visible ? 1 : 0
            self.buttonRow.alpha = visible ? 0 : 1
        }
        flash()
    }

    // MARK: Menus and the Skip capsule

    /// The same menus AVKit's bar shows on the hardware route. Rebuilt menus replace the
    /// buttons' menus in place, so a focused button keeps its focus.
    func setMenus(_ menus: [UIMenu]) {
        let buttons = buttonRow.arrangedSubviews.compactMap { $0 as? TransportMenuButton }
        if buttons.count == menus.count {
            zip(buttons, menus).forEach { $0.setMenu($1) }
            return
        }
        buttons.forEach { $0.removeFromSuperview() }
        for menu in menus {
            let button = TransportMenuButton(menu: menu)
            button.focusable = { [weak self] in self?.rowFocused ?? false }
            buttonRow.addArrangedSubview(button)
        }
        if menus.isEmpty { releaseRow() }
    }

    /// Up from the bar: the row takes focus (and the bar stays up while it has it).
    func focusRow() {
        guard hasMenus else { return }
        setInfo(visible: false)
        rowFocused = true
        dimBar(true)
        flash()
        onFocusChange?()
    }

    /// Down or Menu from the row: focus goes back to the bar.
    func releaseRow() {
        guard rowFocused else { return }
        rowFocused = false
        dimBar(false)
        onFocusChange?()
    }

    /// Skip Intro / Recap / Next Episode: shown (and focused, so Select takes it) while there
    /// is one, with or without the bar, as AVKit's contextual action.
    func setAction(_ action: UIAction?) {
        guard let action else {
            guard let actionButton else { return }
            actionButton.removeFromSuperview()
            self.actionButton = nil
            onFocusChange?()
            return
        }
        if let actionButton { return actionButton.setAction(action) }
        let button = TransportActionButton(action: action)
        button.focusable = { [weak self] in !(self?.rowFocused ?? true) }
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            button.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -30),
        ])
        actionButton = button
        onFocusChange?()
    }

    private func dimBar(_ dimmed: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.fill.alpha = dimmed ? 0.35 : 1
            self.elapsedLabel.textColor = dimmed ? .white.withAlphaComponent(0.6) : .white
        }
    }

    // MARK: Scrub preview

    /// Shows the seek target's thumbnail (if any) above the bar at `time`. A nil image keeps the
    /// previous one until the next arrives; with no thumbnails at all only the target time is shown.
    func showPreview(time: Double, duration: Double, image: UIImage?, hasThumbnails: Bool) {
        guard duration > 0 else { return }
        previewFraction = CGFloat(min(max(time / duration, 0), 1))
        preview.set(time: Self.clock(time), image: image, showsImage: hasThumbnails)
        setNeedsLayout()
        layoutIfNeeded()
        guard preview.alpha < 1 else { return }
        UIView.animate(withDuration: 0.15) {
            self.preview.alpha = 1
            self.buttonRow.alpha = 0
        }
    }

    /// Updates the image for the preview already on screen (a late load).
    func updatePreviewImage(_ image: UIImage) {
        preview.setImage(image)
    }

    func hidePreview() {
        guard preview.alpha > 0 else { return }
        UIView.animate(withDuration: 0.25) {
            self.preview.alpha = 0
            self.buttonRow.alpha = self.isInfoShowing ? 0 : 1
        }
    }

    private func layoutPreview() {
        let size = preview.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let bar = track.convert(track.bounds, to: chrome)
        guard bar.width > 0 else { return }
        let centerX = bar.minX + bar.width * previewFraction
        let x = min(max(centerX - size.width / 2, bar.minX), bar.maxX - size.width)
        preview.frame = CGRect(x: x, y: bar.minY - 30 - size.height, width: size.width, height: size.height)
    }

    // MARK: Transport

    func update(position: Double, duration: Double, paused: Bool) {
        fraction = duration > 0 ? CGFloat(min(max(position / duration, 0), 1)) : 0
        setNeedsLayout()
        elapsedLabel.text = Self.clock(position)
        remainingLabel.text = duration > 0 ? "-" + Self.clock(max(0, duration - position)) : nil
        pauseGlyph.isHidden = !paused
        if paused != self.paused {
            self.paused = paused
            if paused { flash() }
        }
    }

    /// AVKit's clock: "00:04", "1:02:03".
    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.isFinite ? seconds : 0)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// Shows the bar; it auto-hides after a few seconds unless playback is paused, the row has
    /// focus or the Info card is open.
    func flash() {
        hideWork?.cancel()
        UIView.animate(withDuration: 0.2) { self.chrome.alpha = 1 }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !paused, !rowFocused, !isInfoShowing else { return }
            hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Menu with the bar up (and nothing else open) hides it, as AVKit's.
    func hide() {
        hideWork?.cancel()
        releaseRow()
        info.alpha = 0
        buttonRow.alpha = 1
        UIView.animate(withDuration: 0.4) { self.chrome.alpha = 0 }
    }
}
