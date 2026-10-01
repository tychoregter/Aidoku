//
//  FilterLabelView.swift
//  Aidoku
//
//  Created by Skitty on 10/16/23.
//

import SwiftUI
import UIKit

struct FilterLabelView: View {
    let name: String
    var badgeCount: Int?
    var active = false
    var chevron = true
    var icon: String?

    @Environment(\.colorScheme) private var colorScheme

    private var highlighted: Bool {
        active || badgeCount ?? 0 > 0
    }

    // show badge if count (number of subfilters enabled) is greater than 1
    private var hasBadge: Bool {
        badgeCount ?? 1 > 1
    }

    var body: some View {
        let label = HStack(spacing: 4) {
            if let badgeCount, hasBadge {
                FilterBadgeView(count: badgeCount)
            }

            Text(name)
                .foregroundColor(
                    highlighted && colorScheme == .light
                        ? .accentColor
                        : highlighted ? .primary : Color(uiColor: .secondaryLabel)
                )

            Group {
                if let icon {
                    Image(systemName: icon)
                } else if chevron {
                    Image(systemName: "chevron.down")
                }
            }
            .foregroundColor(
                highlighted
                    ? (colorScheme == .light ? .accentColor : .primary)
                    : .init(uiColor: .tertiaryLabel)
            )
        }
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, hasBadge ? 6 : 8)
        .font(.caption.weight(.medium))

        if #available(iOS 26.0, *) {
            label
                .glassEffect(
                    highlighted ? .regular.tint(.accentColor.opacity(highlighted && colorScheme == .light ? 0.1 : 1)) : .regular,
                    in: .capsule
                )
        } else {
            label
                .background(
                    RoundedRectangle(cornerRadius: 100) // enough to make it fully rounded
                        .foregroundColor(
                            highlighted ? .accentColor : .init(uiColor: .secondarySystemFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(Color(uiColor: .tertiarySystemFill), style: .init(lineWidth: 1))
                        )
                        .opacity(highlighted && colorScheme == .light ? 0.1 : 1)
                )
        }
    }
}

// Keep the visible pill and its content in one UIKit button so the menu morph
// animates the title and chevron along with the glass background.
final class LibraryStyleFilterMenuButtonView: UIButton {
    private let pillFont = UIFont.systemFont(ofSize: 12, weight: .medium)
    private var pillSize = CGSize(width: 32, height: 30)
    private var hostedLabel: UIHostingController<FilterLabelView>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsMenuAsPrimaryAction = true
        if #available(iOS 26.0, *) {
            let label = UIHostingController(rootView: FilterLabelView(name: ""))
            label.view.backgroundColor = .clear
            label.view.isUserInteractionEnabled = false
            label.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label.view)
            NSLayoutConstraint.activate([
                label.view.topAnchor.constraint(equalTo: topAnchor),
                label.view.bottomAnchor.constraint(equalTo: bottomAnchor),
                label.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.view.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
            hostedLabel = label
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        pillSize
    }

    func update(title text: String, badgeCount: Int = 0, active: Bool, darkMode: Bool) {
        let accent = UIColor(Color.accentColor)
        let foreground = active && !darkMode ? accent : UIColor.label
        let titleColor = active ? foreground : foreground.withAlphaComponent(0.6)
        let chevronColor = active ? foreground : UIColor.tertiaryLabel
        let symbol = UIImage(
            systemName: "chevron.down",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )?.withTintColor(chevronColor, renderingMode: .alwaysOriginal)
        let hasBadge = badgeCount > 1
        let title = NSMutableAttributedString()
        var badgeWidth: CGFloat = 0
        if hasBadge {
            let badgeImage = makeBadgeImage(count: badgeCount, accent: accent, darkMode: darkMode)
            badgeWidth = badgeImage.size.width + 4
            let attachment = NSTextAttachment()
            attachment.image = badgeImage
            attachment.bounds = CGRect(x: 0, y: -2, width: badgeImage.size.width, height: FilterBadgeView.size)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " ", attributes: [.font: pillFont]))
        }
        title.append(NSAttributedString(string: text, attributes: [
            .font: pillFont,
            .foregroundColor: titleColor
        ]))

        var style: UIButton.Configuration
        if #available(iOS 26.0, *) {
            style = .plain()
            tintColor = active && !darkMode ? accent : .label
            hostedLabel?.rootView = FilterLabelView(
                name: text,
                badgeCount: badgeCount,
                active: active
            )
        } else {
            style = .filled()
            style.baseBackgroundColor = active && darkMode ? accent : .secondarySystemFill
        }
        style.cornerStyle = .capsule
        style.buttonSize = .small
        style.contentInsets = NSDirectionalEdgeInsets(top: hasBadge ? 6 : 8, leading: 9, bottom: hasBadge ? 6 : 8, trailing: 9)
        if #unavailable(iOS 26.0) {
            style.attributedTitle = AttributedString(title)
            style.image = symbol
        }
        style.titleLineBreakMode = .byClipping
        style.imagePlacement = .trailing
        style.imagePadding = 4
        style.indicator = .none
        configuration = style
        if let hostedView = hostedLabel?.view {
            bringSubviewToFront(hostedView)
        }

        let textWidth = (text as NSString).size(withAttributes: [.font: pillFont]).width
        let symbolWidth = symbol?.size.width ?? 0
        pillSize = CGSize(
            // NSString's measured width can be a little narrower than the
            // configured button title's rendered glyphs (notably trailing "g").
            width: ceil(18 + badgeWidth + textWidth + 4 + symbolWidth) + 4,
            height: ceil(max(pillFont.lineHeight, hasBadge ? FilterBadgeView.size : 0) + (hasBadge ? 12 : 16))
        )
        invalidateIntrinsicContentSize()
    }

    private func makeBadgeImage(count: Int, accent: UIColor, darkMode: Bool) -> UIImage {
        let text = String(count)
        let textSize = (text as NSString).size(withAttributes: [.font: pillFont])
        let size = CGSize(width: max(FilterBadgeView.size, ceil(textSize.width) + 10), height: FilterBadgeView.size)
        return UIGraphicsImageRenderer(size: size).image { _ in
            (darkMode ? UIColor.white : accent).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: pillFont,
                .foregroundColor: darkMode ? accent : UIColor.white
            ]
            (text as NSString).draw(at: CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            ), withAttributes: attributes)
        }
    }
}
