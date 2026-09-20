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
    private var showingTemporaryPagesLeft = false
    private var pagesLeftRestoreWorkItem: DispatchWorkItem?
    private var pagesLeftDisplayGeneration = 0
    private var pageCounterMorphAnimator: UIViewPropertyAnimator?

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

        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        thumbnailPageCounterView.effect = glassEffect
        thumbnailPageCounterView.contentView.backgroundColor = .clear
        thumbnailPageCounterView.layer.cornerRadius = 8
        thumbnailPageCounterView.layer.cornerCurve = .continuous
        thumbnailPageCounterView.clipsToBounds = true
        thumbnailPageCounterView.isUserInteractionEnabled = true
        let pageCounterTapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(handlePageCounterTap)
        )
        thumbnailPageCounterView.addGestureRecognizer(pageCounterTapGesture)
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
        cancelTemporaryPagesLeftDisplay()
        updatePageLabels()
        thumbnailPageCounterView.isHidden = !usesThumbnailScrubber
    }

    func finishHidingPageCounter() {
        pageCounterControlsVisible = false
        cancelTemporaryPagesLeftDisplay()
        updatePageLabels()
        thumbnailPageCounterView.isHidden = true
    }

    @objc private func handlePageCounterTap() {
        guard usesThumbnailScrubber,
              pageCounterControlsVisible,
              let totalPages,
              let currentPage = currentPage ?? currentPageValue else { return }

        if showingTemporaryPagesLeft {
            cancelTemporaryPagesLeftDisplay()
            updatePageLabels(animated: true)
            return
        }

        pagesLeftRestoreWorkItem?.cancel()
        pagesLeftDisplayGeneration += 1
        let generation = pagesLeftDisplayGeneration
        showingTemporaryPagesLeft = true
        updatePagesLeftLabel(
            page: min(max(currentPage, 1), totalPages),
            totalPages: totalPages,
            animated: true
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.pagesLeftDisplayGeneration == generation else { return }
            self.showingTemporaryPagesLeft = false
            self.pagesLeftRestoreWorkItem = nil
            self.updatePageLabels(animated: true)
        }
        pagesLeftRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func cancelTemporaryPagesLeftDisplay() {
        pagesLeftRestoreWorkItem?.cancel()
        pagesLeftRestoreWorkItem = nil
        pagesLeftDisplayGeneration += 1
        showingTemporaryPagesLeft = false
    }

    deinit {
        pagesLeftRestoreWorkItem?.cancel()
        pageCounterMorphAnimator?.stopAnimation(true)
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
        if showingTemporaryPagesLeft {
            updatePagesLeftLabel(page: boundedPage, totalPages: totalPages)
        } else if !usesWebtoonProgress || !showsWebtoonScrollPercentage {
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
        if showingTemporaryPagesLeft {
            updatePagesLeftLabel(page: boundedPage, totalPages: totalPages)
        } else {
            thumbnailPageCounterLabel.text = "\(boundedPage) of \(totalPages)"
        }
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

    func updatePageLabels(animated: Bool = false) {
        guard let currentPage, let totalPages else {
            setPageCounterText(nil, animated: animated)
            return
        }

        let boundedPage = min(max(currentPage, 1), totalPages)
        if showingTemporaryPagesLeft {
            updatePagesLeftLabel(page: boundedPage, totalPages: totalPages, animated: animated)
        } else if usesWebtoonProgress, showsWebtoonScrollPercentage {
            updateWebtoonProgressLabel(animated: animated)
        } else {
            updatePageLabel(page: boundedPage, totalPages: totalPages, animated: animated)
        }
    }

    private func updatePageLabel(page: Int, totalPages: Int, animated: Bool = false) {
        setPageCounterText("\(page) of \(totalPages)", animated: animated)
    }

    private func updatePagesLeftLabel(page: Int, totalPages: Int, animated: Bool = false) {
        setPageCounterText("\(max(totalPages - page, 0)) pages left", animated: animated)
    }

    private func setPageCounterText(_ text: String?, animated: Bool) {
        guard thumbnailPageCounterLabel.text != text else { return }
        guard animated, let container = thumbnailPageCounterView.superview else {
            pageCounterMorphAnimator?.stopAnimation(true)
            pageCounterMorphAnimator = nil
            thumbnailPageCounterLabel.text = text
            thumbnailPageCounterView.superview?.layoutIfNeeded()
            return
        }

        pageCounterMorphAnimator?.stopAnimation(false)
        pageCounterMorphAnimator?.finishAnimation(at: .current)
        container.layoutIfNeeded()

        UIView.transition(
            with: thumbnailPageCounterLabel,
            duration: 0.18,
            options: [.transitionCrossDissolve, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.thumbnailPageCounterLabel.text = text
        }

        container.setNeedsLayout()
        let animator = UIViewPropertyAnimator(duration: 0.38, dampingRatio: 0.82) {
            container.layoutIfNeeded()
        }
        pageCounterMorphAnimator = animator
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self, let animator, self.pageCounterMorphAnimator === animator else { return }
            self.pageCounterMorphAnimator = nil
        }
        animator.startAnimation()
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
        if usesWebtoonProgress != enabled || showsWebtoonScrollPercentage != showsPercentage {
            cancelTemporaryPagesLeftDisplay()
        }
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
        if showingTemporaryPagesLeft {
            let page = min(max(currentPage ?? 1, 1), totalPages ?? 1)
            updatePagesLeftLabel(page: page, totalPages: totalPages ?? 1)
        } else if showsWebtoonScrollPercentage {
            updateWebtoonProgressLabel()
        }
        thumbnailScrubberView.accessibilityValue = "\(Int((webtoonProgress * 100).rounded())) percent"
    }

    private func updateWebtoonProgressLabel(animated: Bool = false) {
        setPageCounterText("\(Int((webtoonProgress * 100).rounded()))%", animated: animated)
    }

    func setSliderDirection(_ direction: ReaderThumbnailScrubberView.Direction) {
        thumbnailScrubberView.direction = direction
    }

    func moveSlider(to value: CGFloat) {
        thumbnailScrubberView.move(toValue: value)
    }

    func configureThumbnails(
        contentIdentifier: String,
        pageCount: Int,
        supportsThumbnails: Bool,
        cachedProvider: @escaping (Int) async -> UIImage?,
        provider: @escaping (Int, ReaderThumbnailScrubberView.ImageKind, @escaping @MainActor (UIImage) -> Void) async -> UIImage?
    ) {
        supportsThumbnailScrubber = supportsThumbnails
        thumbnailScrubberView.configure(
            contentIdentifier: contentIdentifier,
            pageCount: pageCount,
            cachedThumbnailProvider: cachedProvider,
            thumbnailProvider: provider
        )
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
