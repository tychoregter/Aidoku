//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

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

    let thumbnailScrubberView = ReaderThumbnailScrubberView()
    var onScrubberStyleChange: ((Bool) -> Void)?
    var onThumbnailScrubberPreferredWidthChange: ((CGFloat?) -> Void)?
    private(set) var usesThumbnailScrubber = false
    let thumbnailPageCounterView = UIVisualEffectView()
    private let thumbnailPageCounterLabel = UILabel()
    private var thumbnailPageCounterPositionConstraints: [NSLayoutConstraint] = []
    private var supportsThumbnailScrubber = false

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        thumbnailScrubberView.semanticContentAttribute = .playback
        thumbnailScrubberView.isHidden = true
        thumbnailScrubberView.onPreviewVisibilityChange = { [weak self] isVisible in
            guard let self else { return }
            if isVisible {
                self.bringSubviewToFront(self.thumbnailScrubberView)
            } else {
                self.thumbnailPageCounterView.superview?.bringSubviewToFront(self.thumbnailPageCounterView)
            }
        }
        addSubview(thumbnailScrubberView)

        if #available(iOS 26.0, *) {
            thumbnailPageCounterView.effect = UIGlassEffect(style: .regular)
        } else {
            thumbnailPageCounterView.effect = UIBlurEffect(style: .systemMaterial)
        }
        thumbnailPageCounterView.layer.cornerRadius = 10
        thumbnailPageCounterView.layer.cornerCurve = .continuous
        thumbnailPageCounterView.clipsToBounds = true
        thumbnailPageCounterView.isUserInteractionEnabled = false
        thumbnailPageCounterView.isHidden = true
        addSubview(thumbnailPageCounterView)

        thumbnailPageCounterLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        thumbnailPageCounterLabel.textColor = .secondaryLabel
        thumbnailPageCounterLabel.textAlignment = .center
        thumbnailPageCounterView.contentView.addSubview(thumbnailPageCounterLabel)
    }

    func constrain() {
        thumbnailScrubberView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPageCounterView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPageCounterLabel.translatesAutoresizingMaskIntoConstraints = false

        thumbnailPageCounterPositionConstraints = [
            thumbnailPageCounterView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailPageCounterView.bottomAnchor.constraint(equalTo: topAnchor, constant: -10)
        ]

        NSLayoutConstraint.activate([
            thumbnailScrubberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailScrubberView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailScrubberView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailScrubberView.bottomAnchor.constraint(equalTo: bottomAnchor),

            thumbnailPageCounterView.heightAnchor.constraint(equalToConstant: 34),
            thumbnailPageCounterView.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            thumbnailPageCounterLabel.leadingAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.leadingAnchor, constant: 12),
            thumbnailPageCounterLabel.trailingAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.trailingAnchor, constant: -12),
            thumbnailPageCounterLabel.topAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.topAnchor),
            thumbnailPageCounterLabel.bottomAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.bottomAnchor)
        ] + thumbnailPageCounterPositionConstraints)
    }

    /// Places the counter inside the same glass container as the reader bar.
    /// Keeping its positional constraints here also makes this easy to reverse.
    func moveThumbnailPageCounter(
        to container: UIView,
        centeredOn centerXAnchor: NSLayoutXAxisAnchor,
        above topAnchor: NSLayoutYAxisAnchor
    ) {
        NSLayoutConstraint.deactivate(thumbnailPageCounterPositionConstraints)
        thumbnailPageCounterView.removeFromSuperview()
        container.addSubview(thumbnailPageCounterView)
        thumbnailPageCounterPositionConstraints = [
            thumbnailPageCounterView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailPageCounterView.bottomAnchor.constraint(equalTo: topAnchor, constant: -10)
        ]
        NSLayoutConstraint.activate(thumbnailPageCounterPositionConstraints)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !thumbnailScrubberView.isHidden,
           thumbnailScrubberView.bounds.contains(convert(point, to: thumbnailScrubberView)) {
            return thumbnailScrubberView
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
        let value = CGFloat(boundedPage - 1) / max(CGFloat(totalPages - 1), 1)
        thumbnailScrubberView.move(toValue: value)
        thumbnailScrubberView.accessibilityValue = "\(boundedPage) of \(totalPages)"
        thumbnailPageCounterLabel.text = "\(boundedPage) of \(totalPages)"
    }

    func setProgressContrastColor(_ color: UIColor) {
        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
        ) {
            self.thumbnailScrubberView.setContrastColor(color)
        }
    }

    func setProgressOverlayAppearance(isDark: Bool) {
        let style: UIUserInterfaceStyle = isDark ? .dark : .light
        thumbnailPageCounterView.overrideUserInterfaceStyle = style
        thumbnailScrubberView.setOverlayAppearance(style)
    }

    func updatePageLabels() {
        guard let currentPage, let totalPages else {
            thumbnailPageCounterLabel.text = nil
            return
        }

        updatePageLabel(page: min(max(currentPage, 1), totalPages), totalPages: totalPages)
    }

    private func updatePageLabel(page: Int, totalPages: Int) {
        thumbnailPageCounterLabel.text = "\(page) of \(totalPages)"
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        moveSlider(to: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }

    func setSliderDirection(_ direction: ReaderThumbnailScrubberView.Direction) {
        thumbnailScrubberView.direction = direction
    }

    func moveSlider(to value: CGFloat) {
        thumbnailScrubberView.move(toValue: value)
    }

    func configureThumbnails(
        pageCount: Int,
        supportsThumbnails: Bool,
        provider: @escaping (Int, ReaderThumbnailScrubberView.ImageKind) async -> UIImage?
    ) {
        supportsThumbnailScrubber = supportsThumbnails
        thumbnailScrubberView.configure(pageCount: pageCount, thumbnailProvider: provider)
        onThumbnailScrubberPreferredWidthChange?(thumbnailScrubberView.preferredWidth)
        thumbnailScrubberView.accessibilityValue = "\(currentPage ?? 1) of \(pageCount)"
        thumbnailScrubberView.isAccessibilityElement = true
        thumbnailScrubberView.accessibilityTraits = .adjustable
        refreshScrubberStyle()
    }

    private func refreshScrubberStyle() {
        let usesThumbnails = supportsThumbnailScrubber
        let styleChanged = usesThumbnails != usesThumbnailScrubber
        usesThumbnailScrubber = usesThumbnails
        thumbnailScrubberView.isHidden = !usesThumbnails
        thumbnailScrubberView.setLoadingEnabled(usesThumbnails)
        thumbnailPageCounterView.isHidden = !usesThumbnails
        if styleChanged {
            onScrubberStyleChange?(usesThumbnails)
        }
        if usesThumbnails {
            onThumbnailScrubberPreferredWidthChange?(thumbnailScrubberView.preferredWidth)
        }
    }
}
