//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

class ReaderToolbarView: UIView {
    private var currentPageValue: Int?
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
    let thumbnailPageCounterView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let thumbnailPageCounterLabel = UILabel()
    private var thumbnailPageCounterPositionConstraints: [NSLayoutConstraint] = []
    private var supportsThumbnailScrubber = false
    private var pageCounterControlsVisible = true
    private var usesWebtoonProgress = false
    private var showsWebtoonScrollPercentage = true
    private var webtoonProgress: CGFloat = 0

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
            // Match the native regular glass used by the reader scrubber.
            thumbnailPageCounterView.effect = UIGlassEffect(style: .regular)
            thumbnailPageCounterView.contentView.backgroundColor = .clear
        } else {
            // Preserve the previous subtly blurred neutral counter as the
            // fallback (and as the direct revert path for the glass design).
            thumbnailPageCounterView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            thumbnailPageCounterView.contentView.backgroundColor = UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return UIColor(white: 0.22, alpha: 0.62)
                }
                return UIColor(white: 0.953, alpha: 0.58)
            }
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

            thumbnailPageCounterView.heightAnchor.constraint(equalToConstant: 30),
            thumbnailPageCounterLabel.leadingAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.leadingAnchor, constant: 11),
            thumbnailPageCounterLabel.trailingAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.trailingAnchor, constant: -11),
            thumbnailPageCounterLabel.topAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.topAnchor),
            thumbnailPageCounterLabel.bottomAnchor.constraint(equalTo: thumbnailPageCounterView.contentView.bottomAnchor)
        ] + thumbnailPageCounterPositionConstraints)
    }

    /// Places the counter in the reader overlay, matching the position used by
    /// native document viewers while keeping it independent of the scrubber.
    func moveThumbnailPageCounter(
        to container: UIView,
        centeredOn centerXAnchor: NSLayoutXAxisAnchor,
        above topAnchor: NSLayoutYAxisAnchor,
        spacing: CGFloat
    ) {
        NSLayoutConstraint.deactivate(thumbnailPageCounterPositionConstraints)
        thumbnailPageCounterView.removeFromSuperview()
        container.addSubview(thumbnailPageCounterView)
        thumbnailPageCounterPositionConstraints = [
            thumbnailPageCounterView.centerXAnchor.constraint(equalTo: centerXAnchor),
            thumbnailPageCounterView.bottomAnchor.constraint(equalTo: topAnchor, constant: -spacing)
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
        if !usesWebtoonProgress || !showsWebtoonScrollPercentage {
            updatePageLabel(page: boundedPage, totalPages: totalPages)
        }
        if currentPageValue != boundedPage,
           (!usesWebtoonProgress || thumbnailScrubberView.isTracking) {
            let feedbackGenerator = UISelectionFeedbackGenerator()
            feedbackGenerator.selectionChanged()
        }
        currentPageValue = boundedPage
        if usesWebtoonProgress {
            thumbnailScrubberView.accessibilityValue = "\(Int((webtoonProgress * 100).rounded())) percent"
            return
        }
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
        if #unavailable(iOS 26.0) {
            thumbnailPageCounterView.overrideUserInterfaceStyle = style
        }
    }

    /// The counter belongs to the top reader controls, so its light/dark state
    /// follows those controls immediately rather than the delayed scrubber
    /// contrast sampling used for page thumbnails.
    func setPageCounterAppearance(isDark: Bool) {
        if #available(iOS 26.0, *) {
            // Native glass follows the same sampled overlay appearance as the
            // scrubber rather than the separate navigation-bar appearance.
            return
        }
        thumbnailPageCounterView.overrideUserInterfaceStyle = isDark ? .dark : .light
    }

    func updatePageLabels() {
        guard let currentPage, let totalPages else {
            thumbnailPageCounterLabel.text = nil
            return
        }

        if usesWebtoonProgress, showsWebtoonScrollPercentage {
            updateWebtoonProgressLabel()
        } else {
            updatePageLabel(page: min(max(currentPage, 1), totalPages), totalPages: totalPages)
        }
    }

    private func updatePageLabel(page: Int, totalPages: Int) {
        thumbnailPageCounterLabel.text = "\(page) of \(totalPages)"
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        if usesWebtoonProgress {
            moveSlider(to: webtoonProgress)
        } else {
            moveSlider(to: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
        }
    }

    func setWebtoonProgressMode(enabled: Bool, showsPercentage: Bool) {
        usesWebtoonProgress = enabled
        showsWebtoonScrollPercentage = showsPercentage
        thumbnailScrubberView.usesContinuousProgress = enabled
        updatePageLabels()
        updateSliderPosition()
    }

    func setWebtoonProgress(_ progress: CGFloat) {
        webtoonProgress = min(max(progress, 0), 1)
        guard usesWebtoonProgress else { return }
        moveSlider(to: webtoonProgress)
        if showsWebtoonScrollPercentage {
            updateWebtoonProgressLabel()
        }
        thumbnailScrubberView.accessibilityValue = "\(Int((webtoonProgress * 100).rounded())) percent"
    }

    private func updateWebtoonProgressLabel() {
        thumbnailPageCounterLabel.text = "\(Int((webtoonProgress * 100).rounded()))%"
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
        if usesWebtoonProgress {
            thumbnailScrubberView.accessibilityValue = "\(Int((webtoonProgress * 100).rounded())) percent"
        } else {
            thumbnailScrubberView.accessibilityValue = "\(currentPage ?? 1) of \(pageCount)"
        }
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
