//
//  ReaderSliderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/20/22.
//

import UIKit

class ReaderSliderView: UIControl {
    var onTrackingStateChanged: ((Bool) -> Void)?

    enum SliderDirection {
        case forward
        case backward
    }

    var direction: SliderDirection = .forward {
        didSet {
            trackPositionConstraint?.isActive = false
            if direction == .forward {
                trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor)
            } else {
                trackPositionConstraint = progressedTrackView.trailingAnchor.constraint(equalTo: trackView.trailingAnchor)
            }
            trackPositionConstraint?.isActive = true
        }
    }

    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    var currentValue: CGFloat = 0 {
        didSet {
            updateLayerFrames()
        }
    }

    private lazy var trackView = {
        let trackView = UIView()
        trackView.backgroundColor = .secondarySystemFill
        trackView.layer.cornerRadius = 4
        trackView.layer.cornerCurve = .continuous
        trackView.clipsToBounds = true
        trackView.isUserInteractionEnabled = true
        return trackView
    }()
    private lazy var progressedTrackView = {
        let progressedTrackView = UIView()
        progressedTrackView.backgroundColor = tintColor
        progressedTrackView.isUserInteractionEnabled = true
        return progressedTrackView
    }()

    private var trackWidthConstraint: NSLayoutConstraint?
    private var trackPositionConstraint: NSLayoutConstraint?
    private var trackHeightConstraint: NSLayoutConstraint?
    private var progressedTrackHeightConstraint: NSLayoutConstraint?

    private var previousLocation = CGPoint()

    override var frame: CGRect {
        didSet {
            updateLayerFrames()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        addSubview(trackView)
        trackView.addSubview(progressedTrackView)
    }

    func constrain() {
        trackView.translatesAutoresizingMaskIntoConstraints = false
        progressedTrackView.translatesAutoresizingMaskIntoConstraints = false

        trackWidthConstraint = progressedTrackView.widthAnchor.constraint(equalToConstant: 5)
        trackWidthConstraint?.isActive = true
        trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor)
        trackPositionConstraint?.isActive = true
        trackHeightConstraint = trackView.heightAnchor.constraint(equalToConstant: 8)
        progressedTrackHeightConstraint = progressedTrackView.heightAnchor.constraint(equalToConstant: 8)

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackHeightConstraint!,

            progressedTrackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressedTrackHeightConstraint!
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrames()
        trackView.layer.cornerRadius = trackView.bounds.height / 2
    }

    override func tintColorDidChange() {
        progressedTrackView.backgroundColor = tintColor
    }

    private func updateLayerFrames() {
        guard trackView.frame.size != .zero else { return }
        let position = positionForValue(currentValue)
        let trackWidth = trackView.bounds.width
        if direction == .forward {
            let rawProgressWidth = position
            let progressWidth = min(trackWidth, max(0, rawProgressWidth))
            trackWidthConstraint?.constant = progressWidth
        } else {
            let rawProgressWidth = trackView.bounds.width - position
            let progressWidth = min(trackWidth, max(0, rawProgressWidth))
            trackWidthConstraint?.constant = progressWidth
        }
    }
}

extension ReaderSliderView {
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        previousLocation = touch.location(in: self)

        tag = 1
        onTrackingStateChanged?(true)
        UIView.animate(withDuration: 0.2) {
            self.trackHeightConstraint?.constant = 16
            self.progressedTrackHeightConstraint?.constant = 16
            self.layoutIfNeeded()
        }
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)

        let deltaLocation = location.x - previousLocation.x
        let deltaValue = (maximumValue - minimumValue) * deltaLocation / bounds.width

        previousLocation = location

        if tag == 1 {
            if direction == .forward {
                currentValue += deltaValue
            } else {
                currentValue -= deltaValue
            }
            currentValue = boundValue(currentValue, toLowerValue: minimumValue, upperValue: maximumValue)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateLayerFrames()

        CATransaction.commit()

        sendActions(for: .valueChanged)

        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        tag = 0
        onTrackingStateChanged?(false)
        UIView.animate(withDuration: 0.2) {
            self.trackHeightConstraint?.constant = 8
            self.progressedTrackHeightConstraint?.constant = 8
            self.layoutIfNeeded()
        }
        sendActions(for: .editingDidEnd)
    }

    override func cancelTracking(with event: UIEvent?) {
        endTracking(nil, with: event)
    }
}

extension ReaderSliderView {
    func move(toValue value: CGFloat) {
        currentValue = value
    }

    private func positionForValue(_ value: CGFloat) -> CGFloat {
        if direction == .forward {
            trackView.bounds.width * value
        } else {
            trackView.bounds.width - (trackView.bounds.width * value)
        }
    }

    private func boundValue(_ value: CGFloat, toLowerValue lowerValue: CGFloat, upperValue: CGFloat) -> CGFloat {
        min(max(value, lowerValue), upperValue)
    }
}
