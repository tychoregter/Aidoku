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

    @EnvironmentObject private var path: NavigationCoordinator
    @State private var expanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var hasHiddenText: Bool {
        textUntilNewline != text || fullHeight > collapsedHeight + 1
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
        Group {
            if expanded {
                markdownView(text)
                    .textSelection(.enabled)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expanded = false
                        }
                    }
                    .transition(.opacity)
            } else {
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
                                VStack(spacing: 0) {
                                    Color.white
                                    HStack(spacing: 0) {
                                        Color.white
                                        LinearGradient(
                                            colors: [.white, .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .frame(width: 52)
                                        Color.clear.frame(width: 38)
                                    }
                                    .frame(height: min(22, geometry.size.height))
                                }
                            }
                        } else {
                            Color.white
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if hasHiddenText {
                            Text(NSLocalizedString("MORE").uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expanded = true
                        }
                    }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
