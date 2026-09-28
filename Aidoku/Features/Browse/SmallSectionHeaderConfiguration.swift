//
//  SmallSectionHeaderConfiguration.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/31/22.
//

import UIKit

struct SmallSectionHeaderConfiguration: UIContentConfiguration {

    var title: String?
    var leadingInset: CGFloat = 0

    func makeContentView() -> UIView & UIContentView {
        SmallSectionHeaderContentView(self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        self
    }
}

class SmallSectionHeaderContentView: UIView, UIContentView {

    var configuration: UIContentConfiguration {
        didSet {
            configure()
        }
    }

    let titleLabel = UILabel()
    private var leadingConstraint: NSLayoutConstraint!

    init(_ configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        titleLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 20, weight: .semibold)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        leadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0),
            leadingConstraint,
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor)
        ])

        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        guard let configuration = configuration as? SmallSectionHeaderConfiguration else { return }
        titleLabel.text = configuration.title
        leadingConstraint.constant = configuration.leadingInset
    }
}
