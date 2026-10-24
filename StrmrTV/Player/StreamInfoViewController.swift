import UIKit

/// The Stream tab beside AVKit's Info tab (swipe down on the hardware route): the file, video,
/// dynamic range, audio and source of what is playing, as label / value rows.
final class StreamInfoViewController: UIViewController {
    private let stack = UIStackView()
    private var info = StreamInfo()

    static let panelHeight: CGFloat = 330
    private static let labelWidth: CGFloat = 260

    init() {
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Stream")
        preferredContentSize = CGSize(width: 0, height: Self.panelHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // AVKit draws the Info tab's card itself but leaves a custom tab bare: the same rounded
        // glass card, filling the panel AVKit gives the tab.
        let card = Self.makeCard()
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.topAnchor.constraint(equalTo: view.topAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 48),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -48),
            stack.centerYAnchor.constraint(equalTo: card.contentView.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: card.contentView.topAnchor, constant: 28),
        ])
        render()
    }

    private static func makeCard() -> UIVisualEffectView {
        let card: UIVisualEffectView
        if #available(tvOS 26.0, *) {
            card = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            card = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        }
        card.layer.cornerRadius = 40
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        card.clipsToBounds = true
        return card
    }

    func update(_ info: StreamInfo) {
        guard info != self.info else { return }
        self.info = info
        if isViewLoaded { render() }
    }

    private func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let rows = info.rows
        guard !rows.isEmpty else {
            stack.addArrangedSubview(Self.valueLabel(String(localized: "Reading the stream…")))
            return
        }
        for row in rows {
            let label = UILabel()
            label.text = row.label
            label.font = .preferredFont(forTextStyle: .callout)
            label.textColor = .secondaryLabel
            label.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
            let value = Self.valueLabel(row.value)
            // The file name is the one long value; let it wrap instead of truncating the tail.
            value.numberOfLines = row.label == String(localized: "File") ? 2 : 1
            let line = UIStackView(arrangedSubviews: [label, value])
            line.spacing = 24
            line.alignment = .firstBaseline
            stack.addArrangedSubview(line)
        }
    }

    private static func valueLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .label
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}
