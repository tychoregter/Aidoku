//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Combine
import UIKit

class ReaderToolbarView: UIView {
    private static let minimumPageLabelWidth: CGFloat = 46
    private static let maximumPageLabelWidth: CGFloat = 88
    private static let pageLabelWidthPadding: CGFloat = 4

    private static let timestampColor = UIColor { traits in
        let base: UIColor = traits.userInterfaceStyle == .dark ? .white : .black
        return base.withAlphaComponent(0.50)
    }

    var currentPageValue: Int? {
        didSet {
            if oldValue != currentPageValue {
                let feedbackGenerator = UISelectionFeedbackGenerator()
                feedbackGenerator.selectionChanged()
            }
        }
    }
    var currentPage: Int? {
        didSet { updatePageLabels() }
    }
    var totalPages: Int? {
        didSet { updatePageLabels() }
    }

    let sliderView = ReaderSliderView()
    private let incognitoModeLabel = UILabel()
    private let currentPageLabel = UILabel()
    private var currentPageLabelWidthConstraint: NSLayoutConstraint?

    private var cancellables: [AnyCancellable] = []

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
        observe()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        incognitoModeLabel.font = .systemFont(ofSize: 10)
        incognitoModeLabel.textColor = .secondaryLabel
        incognitoModeLabel.textAlignment = .left
        incognitoModeLabel.isHidden = !AppSettings.general.incognitoMode.get()
        addSubview(incognitoModeLabel)

        currentPageLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        currentPageLabel.textColor = Self.timestampColor
        currentPageLabel.textAlignment = .right
        currentPageLabel.adjustsFontSizeToFitWidth = true
        currentPageLabel.minimumScaleFactor = 0.8
        currentPageLabel.setContentHuggingPriority(.required, for: .horizontal)
        currentPageLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(currentPageLabel)

        sliderView.semanticContentAttribute = .playback // for rtl languages
        addSubview(sliderView)
        bringSubviewToFront(incognitoModeLabel)
        bringSubviewToFront(currentPageLabel)
    }

    func constrain() {
        incognitoModeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderView.translatesAutoresizingMaskIntoConstraints = false

        let currentPageLabelWidthConstraint = currentPageLabel.widthAnchor.constraint(
            equalToConstant: Self.minimumPageLabelWidth
        )
        self.currentPageLabelWidthConstraint = currentPageLabelWidthConstraint

        NSLayoutConstraint.activate([
            incognitoModeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            incognitoModeLabel.centerYAnchor.constraint(equalTo: sliderView.centerYAnchor),

            currentPageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            currentPageLabelWidthConstraint,
            currentPageLabel.centerYAnchor.constraint(equalTo: sliderView.centerYAnchor),

            sliderView.heightAnchor.constraint(equalTo: heightAnchor),
            sliderView.centerYAnchor.constraint(equalTo: centerYAnchor),
            sliderView.leadingAnchor.constraint(equalTo: currentPageLabel.trailingAnchor, constant: 8),
            sliderView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    func observe() {
        NotificationCenter.default.publisher(for: .init(AppSettings.general.incognitoMode.key))
            .sink { [weak self] _ in
                self?.incognitoModeLabel.isHidden = !AppSettings.general.incognitoMode.get()
            }
            .store(in: &cancellables)
    }

    // allow slider thumb to be touched outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews where subview is ReaderSliderView {
            if subview.bounds.contains(convert(point, to: subview)) {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }

    func displayPage(_ page: Int) {
        guard let totalPages = totalPages else {
            return
        }
        let boundedPage = min(max(page, 1), totalPages)
        updatePageLabel(page: boundedPage, totalPages: totalPages)
        currentPageValue = boundedPage
    }

    func updatePageLabels() {
        guard let currentPage, let totalPages else {
            currentPageLabel.text = nil
            return
        }

        updatePageLabel(page: min(max(currentPage, 1), totalPages), totalPages: totalPages)
        incognitoModeLabel.text = NSLocalizedString("INCOGNITO_MODE")
    }

    private func updatePageLabel(page: Int, totalPages: Int) {
        currentPageLabel.text = "\(page) / \(totalPages)"

        // Reserve enough room for the widest value this title can display so
        // advancing between pages never shifts the progress bar.
        let maximumText = "\(totalPages) / \(totalPages)" as NSString
        let measuredWidth = ceil(maximumText.size(withAttributes: [.font: currentPageLabel.font as Any]).width)
            + Self.pageLabelWidthPadding
        currentPageLabelWidthConstraint?.constant = min(
            max(measuredWidth, Self.minimumPageLabelWidth),
            Self.maximumPageLabelWidth
        )
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        sliderView.move(toValue: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }
}
