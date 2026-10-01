//
//  ExpandableTextView.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import MarkdownUI
import SafariServices
import SwiftUI

struct ExpandableTextView: View {
    let text: String
    var textColor: Color = .secondary
    var moreTextColor: Color = .white
    var onExpansionAnimationChange: ((Bool) -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var expandedHeight: CGFloat = 0

    private var hasHiddenText: Bool {
        textUntilNewline != text || fullHeight > collapsedHeight + 1
    }

    private var moreLabel: String { NSLocalizedString("MORE").uppercased() }

    private var moreFont: UIFont { .systemFont(ofSize: 13, weight: .semibold) }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        onExpansionAnimationChange?(true)
        withAnimation(
            reduceMotion ? nil : .easeInOut(duration: 0.28),
            completionCriteria: .logicallyComplete
        ) {
            expanded = value
        } completion: {
            onExpansionAnimationChange?(false)
        }
    }

    private var moreLabelWidth: CGFloat {
        (moreLabel as NSString).size(withAttributes: [.font: moreFont]).width
    }

    private func moreStartX(in width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }

        let textStorage = NSTextStorage(
            string: textUntilNewline,
            attributes: [.font: UIFont.systemFont(ofSize: 15)]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        var lastLineEnd: CGFloat = 0
        var lineCount = 0
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { _, usedRect, _, _, stop in
            lastLineEnd = usedRect.maxX
            lineCount += 1
            if lineCount == 3 { stop.pointee = true }
        }

        return min(lastLineEnd + 5, max(0, width - moreLabelWidth))
    }

    var textUntilNewline: String {
        // first three lines up to either new paragraph or separator
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .prefix(3)
            .prefix { !$0.isEmpty && !$0.contains("___") }
            .joined(separator: "  \n")
    }

    private var markdownTheme: Theme {
        Theme()
            .paragraph { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(15)
                    }
                    .lineSpacing(0)
                    .foregroundStyle(textColor)
            }
    }

    var body: some View {
        collapsedView
            .opacity(expanded ? 0 : 1)
            .allowsHitTesting(!expanded)
            .overlay(alignment: .topLeading) {
                markdownView(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        expandedHeight = height
                    }
                    .opacity(expanded ? 1 : 0)
                    .contentShape(Rectangle())
                    .allowsHitTesting(expanded)
            }
            .frame(
                height: expanded && expandedHeight > 0
                    ? expandedHeight : (collapsedHeight > 0 ? collapsedHeight : nil),
                alignment: .top
            )
            .clipped()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedView: some View {
        markdownView(textUntilNewline)
            .lineLimit(3)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                collapsedHeight = height
            }
            .background {
                markdownView(textUntilNewline)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        fullHeight = height
                    }
            }
            .mask {
                if hasHiddenText {
                    GeometryReader { geometry in
                        let moreX = moreStartX(in: geometry.size.width)
                        let fadeWidth = min(52, moreX)
                        VStack(spacing: 0) {
                            Color.white
                            HStack(spacing: 0) {
                                Color.white.frame(width: moreX - fadeWidth)
                                LinearGradient(
                                    colors: [.white, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: fadeWidth)
                                Color.clear
                            }
                            .frame(height: min(22, geometry.size.height))
                        }
                    }
                } else {
                    Color.white
                }
            }
            .overlay {
                if hasHiddenText {
                    GeometryReader { geometry in
                        Text(moreLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(moreTextColor)
                            .position(
                                x: moreStartX(in: geometry.size.width) + moreLabelWidth / 2,
                                y: geometry.size.height - moreFont.lineHeight / 2
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { setExpanded(true) }
    }

    private func markdownView(_ content: String) -> some View {
        Markdown(content)
            .markdownTheme(markdownTheme)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard let appDelegate = UIApplication.shared.appDelegate else {
                        return .systemAction
                    }

                    Task {
                        let deepLinkHandled = await appDelegate.handleDeepLink(url: url)
                        if !deepLinkHandled && (url.scheme == "http" || url.scheme == "https") {
                            path.present(SFSafariViewController(url: url))
                        }
                    }

                    return .handled
                }
            )
            .lineSpacing(0)
            .foregroundStyle(textColor)
            .foregroundColor(textColor)
            .font(.subheadline)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
