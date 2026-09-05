//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import Combine
import UIKit

class ReaderToolbarView: UIView {
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

        currentPageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        currentPageLabel.textColor = UIColor.label.withAlphaComponent(0.35)
        currentPageLabel.textAlignment = .right
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

        NSLayoutConstraint.activate([
            incognitoModeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            incognitoModeLabel.centerYAnchor.constraint(equalTo: sliderView.centerYAnchor),

            currentPageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            currentPageLabel.widthAnchor.constraint(equalToConstant: 46),
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
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        sliderView.move(toValue: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }
}
