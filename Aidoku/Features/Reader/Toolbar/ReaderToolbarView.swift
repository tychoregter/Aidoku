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
    let thumbnailPageCounterView = UIView()
    private let thumbnailPageCounterLabel = UILabel()
    private var thumbnailPageCounterPositionConstraints: [NSLayoutConstraint] = []
    private var supportsThumbnailScrubber = false
    private var pageCounterControlsVisible = true

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

        // Use a neutral gray rather than systemGray6, whose slight blue tint is
        // noticeably different from the document-viewer counter.
        thumbnailPageCounterView.backgroundColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(white: 0.22, alpha: 1)
            }
            return UIColor(white: 0.953, alpha: 1)
        }
        thumbnailPageCounterView.layer.cornerRadius = 8
        thumbnailPageCounterView.layer.cornerCurve = .continuous
        thumbnailPageCounterView.clipsToBounds = true
        thumbnailPageCounterView.isUserInteractionEnabled = false
        thumbnailPageCounterView.isHidden = true
        addSubview(thumbnailPageCounterView)

        thumbnailPageCounterLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        thumbnailPageCounterLabel.textColor = .secondaryLabel
        thumbnailPageCounterLabel.textAlignment = .center
        thumbnailPageCounterView.addSubview(thumbnailPageCounterLabel)
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

            thumbnailPageCounterView.heightAnchor.constraint(equalToConstant: 30),
            thumbnailPageCounterLabel.leadingAnchor.constraint(equalTo: thumbnailPageCounterView.leadingAnchor, constant: 11),
            thumbnailPageCounterLabel.trailingAnchor.constraint(equalTo: thumbnailPageCounterView.trailingAnchor, constant: -11),
            thumbnailPageCounterLabel.topAnchor.constraint(equalTo: thumbnailPageCounterView.topAnchor),
            thumbnailPageCounterLabel.bottomAnchor.constraint(equalTo: thumbnailPageCounterView.bottomAnchor)
        ] + thumbnailPageCounterPositionConstraints)
    }

    /// Places the counter in the reader overlay, matching the position used by
    /// native document viewers while keeping it independent of the scrubber.
    func moveThumbnailPageCounter(
        to container: UIView,
        trailingTo trailingAnchor: NSLayoutXAxisAnchor,
        topTo topAnchor: NSLayoutYAxisAnchor,
        topOffset: CGFloat
    ) {
        NSLayoutConstraint.deactivate(thumbnailPageCounterPositionConstraints)
        thumbnailPageCounterView.removeFromSuperview()
        container.addSubview(thumbnailPageCounterView)
        thumbnailPageCounterPositionConstraints = [
            thumbnailPageCounterView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            thumbnailPageCounterView.topAnchor.constraint(equalTo: topAnchor, constant: topOffset)
        ]
        NSLayoutConstraint.activate(thumbnailPageCounterPositionConstraints)
        container.bringSubviewToFront(thumbnailPageCounterView)
    }

    func preparePageCounterForShowing() {
        pageCounterControlsVisible = true
        thumbnailPageCounterView.isHidden = !usesThumbnailScrubber
    }

    func finishHidingPageCounter() {
        pageCounterControlsVisible = false
        thumbnailPageCounterView.isHidden = true
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
        thumbnailScrubberView.setOverlayAppearance(style)
    }

    /// The counter belongs to the top reader controls, so its light/dark state
    /// follows those controls immediately rather than the delayed scrubber
    /// contrast sampling used for page thumbnails.
    func setPageCounterAppearance(isDark: Bool) {
        thumbnailPageCounterView.overrideUserInterfaceStyle = isDark ? .dark : .light
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
        thumbnailPageCounterView.isHidden = !usesThumbnails || !pageCounterControlsVisible
        if styleChanged {
            onScrubberStyleChange?(usesThumbnails)
        }
        if usesThumbnails {
            onThumbnailScrubberPreferredWidthChange?(thumbnailScrubberView.preferredWidth)
        }
    }
}
