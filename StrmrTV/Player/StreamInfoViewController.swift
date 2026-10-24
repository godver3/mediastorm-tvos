import UIKit

/// The Stream tab beside AVKit's Info tab (swipe down on the hardware route): the file, video,
/// dynamic range, audio and source of what is playing, as label / value rows.
final class StreamInfoViewController: UIViewController {
    private let stack = UIStackView()
    private var info = StreamInfo()

    static let panelHeight: CGFloat = 360
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
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 60),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -30),
        ])
        render()
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
