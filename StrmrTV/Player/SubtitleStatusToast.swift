import UIKit

/// The online-subtitle status line ("Searching for subtitles…", "Subtitles ready") in the
/// player's top-right corner, over both routes' video and chrome. Passes touches and focus by.
final class SubtitleStatusToast: UIView {
    private let label = UILabel()
    private let icon = UIImageView(image: UIImage(systemName: "captions.bubble"))
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false

        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.layer.cornerRadius = 22
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        label.font = .systemFont(ofSize: 26, weight: .medium)
        label.textColor = .white
        label.accessibilityIdentifier = "subtitleStatus"
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 14
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 26),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -26),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Pins the toast to `host`'s top-right corner.
    func install(in host: UIView) {
        host.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor, constant: 60),
            trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -80),
        ])
    }

    /// Shows `text`; it fades out after `hideAfter` seconds, or stays until the next call.
    func show(_ text: String, hideAfter: TimeInterval?) {
        hideWork?.cancel()
        label.text = text
        superview?.bringSubviewToFront(self)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        guard let hideAfter else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        UIView.animate(withDuration: 0.4) { self.alpha = 0 }
    }
}
