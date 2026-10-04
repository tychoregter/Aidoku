//
//  ReaderTransitionNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/22/23.
//

import AidokuRunner
import AsyncDisplayKit

struct Transition {
    enum TransitionType {
        case next, prev
    }

    var type: TransitionType
    var from: AidokuRunner.Chapter
    var to: AidokuRunner.Chapter?
}

class ReaderTransitionNode: ASDisplayNode {
    var transition: Transition
    var referenceWidth: CGFloat = 0
    private var usesDarkAppearance: Bool

    private var primaryTextColor: UIColor { usesDarkAppearance ? .white : .black }
    private var secondaryTextColor: UIColor { primaryTextColor.withAlphaComponent(0.6) }

    private static let defaultFontSize: CGFloat = 16
    private lazy var fontSize = Self.defaultFontSize
    private var lastWidth: CGFloat = 0

    lazy var topChapterTextNode: ASTextNode = {
        let node = ASTextNode()
        node.attributedText = NSAttributedString(
            string: transition.type == .prev
                ? NSLocalizedString("PREVIOUS_COLON")
                : NSLocalizedString("FINISHED_COLON"),
            attributes: [
                .foregroundColor: primaryTextColor,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize, weight: .medium)
            ]
        )
        return node
    }()

    lazy var topChapterTitleTextNode: ASTextNode = {
        let node = ASTextNode()
        guard
            let chapter = transition.type == .prev
                ? transition.to
                : transition.from
                else {
            return node
        }
        node.attributedText = NSAttributedString(
            string: chapter.readerTransitionDisplayTitle,
            attributes: [
                .foregroundColor: secondaryTextColor,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize)
            ]
        )
        node.maximumNumberOfLines = 2
        return node
    }()

    lazy var bottomChapterTextNode: ASTextNode = {
        let node = ASTextNode()
        node.attributedText = NSAttributedString(
            string: transition.type == .prev
                ? NSLocalizedString("CURRENT_COLON")
                : NSLocalizedString("NEXT_COLON"),
            attributes: [
                .foregroundColor: primaryTextColor,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize, weight: .medium)
            ]
        )
        return node
    }()

    lazy var bottomChapterTitleTextNode: ASTextNode = {
        let node = ASTextNode()
        guard
            let chapter = transition.type == .prev
                ? transition.from
                : transition.to
        else {
            return node
        }
        node.attributedText = NSAttributedString(
            string: chapter.readerTransitionDisplayTitle,
            attributes: [
                .foregroundColor: secondaryTextColor,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize)
            ]
        )
        node.maximumNumberOfLines = 2
        return node
    }()

    lazy var noChapterTextNode: ASTextNode = {
        let node = ASTextNode()
        node.attributedText = NSAttributedString(
            string: transition.type == .prev
                ? NSLocalizedString("NO_PREVIOUS_CHAPTER")
                : NSLocalizedString("NO_NEXT_CHAPTER"),
            attributes: [
                .foregroundColor: secondaryTextColor,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize)
            ]
        )
        return node
    }()

    private var skippedBooksCount: Int {
        guard let to = transition.to else { return 0 }
        return BookGapPresentation.missingCount(between: transition.from, and: to)
    }

    private lazy var warningIconNode: ASImageNode = {
        let node = ASImageNode()
        if let symbol = UIImage(systemName: "exclamationmark.triangle.fill")?
            .withTintColor(.systemOrange, renderingMode: .alwaysOriginal) {
            // Texture does not reliably honor the tint of a vector SF Symbol.
            // Rasterize it so the orange pixels survive its image rendering path.
            node.image = UIGraphicsImageRenderer(size: symbol.size).image { _ in
                symbol.draw(in: CGRect(origin: .zero, size: symbol.size))
            }
        }
        node.style.preferredSize = CGSize(width: Self.defaultFontSize, height: Self.defaultFontSize)
        return node
    }()

    private lazy var warningSpaceNode = ASDisplayNode()

    private lazy var warningTextNode: ASTextNode = {
        let node = ASTextNode()
        let text = skippedBooksCount == 1
            ? NSLocalizedString("SKIPPING_ONE_MISSING_BOOK")
            : String(format: NSLocalizedString("SKIPPING_CHAPTERS"), skippedBooksCount)
        node.attributedText = NSAttributedString(string: text, attributes: [
            .foregroundColor: UIColor.systemOrange,
            .font: UIFont.systemFont(ofSize: Self.defaultFontSize)
        ])
        node.maximumNumberOfLines = 2
        return node
    }()

    init(transition: Transition, usesDarkAppearance: Bool) {
        self.transition = transition
        self.usesDarkAppearance = usesDarkAppearance
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .clear
    }

    func updateAppearance(usesDarkAppearance: Bool) {
        guard self.usesDarkAppearance != usesDarkAppearance else { return }
        self.usesDarkAppearance = usesDarkAppearance

        for (node, color) in [
            (topChapterTextNode, primaryTextColor),
            (topChapterTitleTextNode, secondaryTextColor),
            (bottomChapterTextNode, primaryTextColor),
            (bottomChapterTitleTextNode, secondaryTextColor),
            (noChapterTextNode, secondaryTextColor)
        ] {
            guard let text = node.attributedText?.mutableCopy() as? NSMutableAttributedString else { continue }
            text.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: text.length))
            node.attributedText = text
        }
    }

    override func layout() {
        super.layout()
        if frame.width != lastWidth {
            lastWidth = frame.width

            let referenceWidth = max(referenceWidth, frame.width, 1)
            let widthRatio = min(frame.width / referenceWidth, 1)
            fontSize = Self.defaultFontSize * (2 + widthRatio) / 3

            func fixText(node: ASTextNode) {
                if let attr = node.attributedText?.mutableCopy() as? NSMutableAttributedString {
                    attr.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize), range: NSRange(0..<attr.length))
                    node.attributedText = attr
                }
            }
            fixText(node: topChapterTextNode)
            fixText(node: topChapterTitleTextNode)
            fixText(node: bottomChapterTextNode)
            fixText(node: bottomChapterTitleTextNode)
            fixText(node: noChapterTextNode)
            if skippedBooksCount > 0 {
                fixText(node: warningTextNode)
                warningIconNode.style.preferredSize = CGSize(width: fontSize, height: fontSize)
            }
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if transition.to == nil {
            return ASCenterLayoutSpec(
                horizontalPosition: .center,
                verticalPosition: .center,
                sizingOption: [],
                child: noChapterTextNode
            )
        } else {
            var rows: [ASLayoutElement] = [
                ASStackLayoutSpec(
                    direction: .vertical,
                    spacing: 2,
                    justifyContent: .center,
                    alignItems: .start,
                    children: [topChapterTextNode, topChapterTitleTextNode]
                )
            ]
            if skippedBooksCount > 0 {
                warningSpaceNode.style.preferredSize = CGSize(width: 1, height: fontSize)
                rows.append(warningSpaceNode)
            }
            rows.append(ASStackLayoutSpec(
                direction: .vertical,
                spacing: 2,
                justifyContent: .center,
                alignItems: .start,
                children: [bottomChapterTextNode, bottomChapterTitleTextNode]
            ))
            let content = ASCenterLayoutSpec(
                horizontalPosition: .center,
                verticalPosition: .center,
                sizingOption: skippedBooksCount > 0 ? [] : .minimumWidth,
                child: ASStackLayoutSpec(
                    direction: .vertical,
                    spacing: fontSize * 7/8,
                    justifyContent: .center,
                    alignItems: .start,
                    children: rows
                )
            )
            let centeredContent: ASLayoutSpec
            if skippedBooksCount > 0 {
                content.style.width = ASDimensionMakeWithFraction(1)
                let warning = ASStackLayoutSpec(
                    direction: .horizontal,
                    spacing: fontSize / 2,
                    justifyContent: .center,
                    alignItems: .center,
                    children: [warningIconNode, warningTextNode]
                )
                centeredContent = ASOverlayLayoutSpec(
                    child: content,
                    overlay: ASCenterLayoutSpec(
                        horizontalPosition: .center,
                        verticalPosition: .center,
                        sizingOption: [],
                        child: warning
                    )
                )
            } else {
                centeredContent = content
            }
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: fontSize, left: fontSize * 2, bottom: fontSize, right: fontSize * 2),
                child: centeredContent
            )
        }
    }
}
